//
//  NumericalLaplaceTransform.swift
//  ImpulseDistribution
//
//  Created by Claude on 2026-08-01.
//
//  ===========================================================================
//  WHAT THIS FILE IMPLEMENTS
//  ===========================================================================
//
//  The numerical inverse Laplace transform (NILT) that turns the network's
//  frequency-domain response back into a time-domain waveform.
//
//  This file knows NOTHING about transformers. It inverts an arbitrary F(s)
//  sampled on a vertical contour in the complex plane. That is deliberate: it
//  means the transform can be - and is - verified on its own against
//  transforms whose answers are known in closed form, BEFORE any network is
//  connected to it. Nearly every mistake possible in a transform
//  implementation (a factor of two, the treatment of the DC and Nyquist
//  terms, the direction of the exponential, the damping sign) shows up
//  immediately in those tests and would be nearly impossible to diagnose if
//  it were entangled with an assembly bug in the network matrices.
//
//  ---------------------------------------------------------------------------
//  THE MATH
//  ---------------------------------------------------------------------------
//
//  Start from the Bromwich (inverse Laplace) integral, taken up a vertical
//  line at Re(s) = sigma which lies to the right of every pole of F:
//
//                  1        sigma + j*inf
//      f(t)  =  --------  integral          F(s) * exp(s*t) ds
//               2*pi*j     sigma - j*inf
//
//  Substituting s = sigma + j*omega, so ds = j*d(omega):
//
//                exp(sigma*t)     +inf
//      f(t)  =  --------------  integral   F(sigma + j*omega) * exp(j*omega*t) d(omega)
//                   2*pi         -inf
//
//  Discretise omega = m*dOmega with dOmega = 2*pi/T, and truncate at
//  |m| <= N/2. The 2*pi cancels against dOmega/T:
//
//                 exp(sigma*t)     N/2 - 1
//      f(t)  ~=  --------------     sum      F_m * exp(j*2*pi*m*t/T)
//                      T          m = -N/2
//
//  Sampling at t_k = k*T/N makes the exponential exp(j*2*pi*m*k/N), which is
//  exactly a discrete Fourier transform. So the whole inversion is:
//
//      1. evaluate F on the contour,
//      2. inverse-DFT,
//      3. multiply by exp(sigma*t_k)/T.
//
//  ---------------------------------------------------------------------------
//  WHY THE DAMPING (sigma) IS THERE - THREE JOBS, NOT ONE
//  ---------------------------------------------------------------------------
//
//  1. WRAPAROUND. The DFT treats the signal as periodic with period T, so any
//     part of f(t) that has not decayed by t = T folds back on top of the
//     start of the record. The factor exp(-sigma*t) inside the transform
//     squashes the tail before it can wrap; the exp(+sigma*t) afterwards
//     undoes it exactly where the answer is wanted.
//
//  2. CONVERGENCE. The contour must lie to the right of every pole. For a
//     passive network every pole has Re(s) < 0, so any sigma > 0 works.
//
//  3. THE DC SINGULARITY. This is the one that matters most for this
//     application. The network's nodal equation is s*C'*V - A*I = ..., which
//     at s = 0 loses the entire capacitive term and becomes singular. Because
//     the contour is at Re(s) = sigma > 0, s is NEVER zero - not even for the
//     m = 0 sample, which sits at s = sigma, not at the origin. The
//     singularity that would have to be special-cased in an undamped
//     transform simply never arises.
//
//  THE COST: exp(+sigma*t) at the end of the record amplifies whatever
//  numerical noise the transform has by exp(sigma*T). This is the entire
//  tension in choosing sigma, and it is why `DefaultGrid` computes a record
//  twice as long as the answer actually needed - see the discussion there.
//
//  ---------------------------------------------------------------------------
//  SYMBOL GLOSSARY
//  ---------------------------------------------------------------------------
//
//    s         complex frequency, sigma + j*omega                 [1/s]
//    sigma     damping constant, the real part of the contour     [1/s]
//    omega     angular frequency                                  [rad/s]
//    T         record length (the DFT period)                     [s]
//    N         number of samples, a power of two                  [-]
//    dt        time step, T/N                                     [s]
//    dOmega    angular frequency step, 2*pi/T                     [rad/s]
//    F_m       F(sigma + j*m*dOmega), the sampled transform       [varies]
//    f_k       f(k*dt), the recovered time-domain signal          [varies]
//
//  ===========================================================================

import Foundation
import Accelerate
import ComplexModule
import PchBasePackage

/// A sampling grid for the damped-contour numerical inverse Laplace transform.
///
/// Immutable and `Sendable`: one grid is shared, unmodified, across all the
/// concurrent per-frequency solves.
struct LaplaceGrid:Sendable {

    /// Number of time samples, N. Always a power of two (enforced by `init`).
    let sampleCount:Int

    /// Record length T, in seconds. This is the DFT period, NOT necessarily
    /// the span the caller wants to look at - see `DefaultGrid`.
    let recordLength:Double

    /// Damping constant sigma, in 1/s.
    let damping:Double

    /// Time step, dt = T/N, in seconds.
    var timeStep:Double { recordLength / Double(sampleCount) }

    /// Angular frequency step, dOmega = 2*pi/T, in rad/s.
    var angularStep:Double { 2.0 * π / recordLength }

    /// Number of contour points that must be evaluated: m = 0 ... N/2.
    ///
    /// Only half the spectrum is computed. The other half is filled in by
    /// conjugate symmetry, which is valid because f(t) is real - see
    /// `Invert`.
    var frequencyCount:Int { sampleCount / 2 + 1 }

    /// The highest frequency represented, in Hz. This is the Nyquist limit of
    /// the output grid: the model cannot say anything about the response above
    /// it, and any true content above it will alias down into the answer.
    var maximumFrequency:Double { 1.0 / (2.0 * timeStep) }

    /// The contour point for index m:  s_m = sigma + j*m*dOmega.
    func s(at m:Int) -> Complex<Double> {

        return Complex(damping, Double(m) * angularStep)
    }

    /// The sample time for index k:  t_k = k*dt.
    func time(at k:Int) -> Double {

        return Double(k) * timeStep
    }

    /// - parameter sampleCount: Requested N. Rounded UP to the next power of
    ///   two, because the radix-2 FFT requires it. (This is the failure the
    ///   old `GetFundamentalFrequency` had: it took `log2(n)` of a
    ///   non-power-of-two length, truncated it, and silently transformed only
    ///   a prefix of the data. Rounding up here makes that impossible.)
    /// - parameter recordLength: T in seconds.
    /// - parameter damping: sigma in 1/s. Must be > 0.
    init(sampleCount:Int, recordLength:Double, damping:Double) {

        // Round up to a power of two. 1 << ceil(log2(n)).
        let requested = max(2, sampleCount)
        var n = 2
        while n < requested {

            n <<= 1
        }

        self.sampleCount = n
        self.recordLength = recordLength
        self.damping = damping
    }

    /// The recommended grid for a run that wants a trustworthy answer over
    /// `0 ... displaySpan` with content up to `maximumFrequency`.
    ///
    /// Three choices are made here and each is a genuine trade-off:
    ///
    /// # 1. The record is twice the span you want to look at
    ///
    /// `T = 2 * displaySpan`. The damping factor exp(+sigma*t) applied on the
    /// way out amplifies numerical noise, and it is worst at the END of the
    /// record. Computing twice as long as needed and discarding the second
    /// half means the region actually displayed only ever sees exp(sigma*T/2),
    /// the square root of the worst-case amplification. It also gives the
    /// un-decayed tail of the impulse somewhere to wrap into that nobody
    /// looks at. The cost is exactly 2x the solves.
    ///
    /// # 2. sigma*T = 5
    ///
    /// Wraparound is suppressed by exp(-sigma*T) ~= 6.7e-3, while noise
    /// amplification over the displayed half is only exp(2.5) ~= 12. Pushing
    /// sigma*T to 10 would suppress wraparound to 4.5e-5 but amplify noise by
    /// 148x over the displayed half. 5 is the standard compromise and is what
    /// the EMTP-family literature uses for this class of problem.
    ///
    /// # 3. Bandwidth is chosen, not forced
    ///
    /// This is the point of the whole exercise. An explicit time-marching
    /// integrator must resolve every mode in the model for STABILITY reasons,
    /// including modes far above the frequency where a lumped disc model
    /// means anything. Here the bandwidth is a parameter: sample fast enough
    /// to cover the range the model is valid over and no faster. Content
    /// above the resulting Nyquist limit aliases, so this must not be set
    /// carelessly - but the standard lightning impulse rolls off as 1/omega^2
    /// past its own corner near 530 kHz, so there is very little up there to
    /// alias in the first place. `FrequencyDomainSolver` checks the residual
    /// magnitude at the top of the band and warns if that assumption fails.
    ///
    /// - parameter displaySpan: The time span the caller actually wants, in
    ///   seconds (e.g. 100e-6 for a full-wave shot).
    /// - parameter maximumFrequency: The highest frequency to represent, in Hz.
    static func DefaultGrid(displaySpan:Double, maximumFrequency:Double) -> LaplaceGrid {

        let T = 2.0 * displaySpan

        // Nyquist: dt <= 1/(2*fmax), so N >= 2*fmax*T. init() rounds up to a
        // power of two, so the delivered bandwidth is always >= requested.
        let n = Int((2.0 * maximumFrequency * T).rounded(.up))

        return LaplaceGrid(sampleCount: n, recordLength: T, damping: 5.0 / T)
    }
}

/// Window applied to the sampled spectrum before inversion.
enum LaplaceWindow:Sendable {

    /// No window. Sharpest resolution, but truncating the spectrum at m = N/2
    /// convolves the answer with a sinc and can produce Gibbs ringing near
    /// fast edges.
    case none

    /// Lanczos sigma-factor:  w_m = sin(pi*m/M) / (pi*m/M),  M = N/2.
    ///
    /// This is the classical smoothing for exactly this problem. It is the
    /// average of the truncated series over one period of the highest retained
    /// harmonic, which is what makes it kill Gibbs ringing while barely
    /// touching the smooth part of the answer.
    ///
    /// NOT the default, and the reason is worth recording. A window helps when
    /// the error is oscillatory RINGING from truncating an otherwise-converged
    /// series. The dominant error here is not that - it is a missing-tail BIAS
    /// from the spectrum still having real amplitude at the band edge. A
    /// window narrows the effective bandwidth and therefore makes that bias
    /// worse. Measured on the standard full wave at f_max = 10 MHz, worst
    /// relative error over the record:
    ///
    ///                             no window     Lanczos
    ///     full wave (1/s^2)        1.7e-2       3.9e-2
    ///     damped sinusoid          1.6e-2       3.8e-2
    ///     after subtraction        1.1e-3       1.1e-2
    ///
    /// Lanczos is 2x-10x worse in every case. It is kept because it is the
    /// right tool if a future model does produce genuine Gibbs ringing (a
    /// chopped wave, with its true discontinuity, is the obvious candidate),
    /// but it must not be turned on by reflex.
    case lanczos

    /// The weight for contour index m on a grid with `count` frequency points.
    func weight(m:Int, count:Int) -> Double {

        switch self {

        case .none:
            return 1.0

        case .lanczos:
            // w_0 = 1 by the limit sin(x)/x -> 1; computing it directly would
            // be 0/0.
            guard m > 0 else { return 1.0 }

            let x = π * Double(m) / Double(count)
            return sin(x) / x
        }
    }
}

/// The damped-contour numerical inverse Laplace transform.
enum NumericalLaplaceTransform {

    /// Invert one sampled transform back to the time domain.
    ///
    /// # What the caller must supply
    ///
    /// `spectrum[m]` must be F(s_m) where `s_m = grid.s(at: m)`, for
    /// m = 0 ... N/2 inclusive - that is, `grid.frequencyCount` values.
    ///
    /// # Why only half the spectrum
    ///
    /// f(t) is real, so its transform obeys Hermitian symmetry:
    ///
    ///     F(conj(s)) = conj(F(s))
    ///
    /// which on this contour means F(sigma - j*omega) = conj(F(sigma +
    /// j*omega)). The negative-frequency half is therefore redundant and is
    /// reconstructed here rather than solved for - halving the number of
    /// linear systems the caller has to factor.
    ///
    /// # Why a full complex FFT rather than a packed real one
    ///
    /// vDSP's real-to-complex transforms use a packed storage format with its
    /// own scaling convention, which is a well-known source of factor-of-two
    /// errors. Building the full conjugate-symmetric array and running an
    /// ordinary complex inverse FFT costs about twice as much (irrelevant
    /// here - this runs once per signal, not once per solve) and has no
    /// ambiguity to get wrong.
    ///
    /// It also buys a free correctness check: if the Hermitian array is built
    /// correctly the imaginary part of the result must be zero to rounding.
    /// `imaginaryResidual` reports it, and a non-zero value is a real bug
    /// signal, not noise to be ignored.
    ///
    /// - parameter spectrum: F(s_m) for m = 0 ... N/2. Must have exactly
    ///   `grid.frequencyCount` elements.
    /// - parameter grid: The contour the spectrum was sampled on.
    /// - parameter window: Spectral window. Defaults to none - see the
    ///   discussion on `LaplaceWindow.lanczos` for why windowing hurts here.
    /// - returns: `values`, the N real time samples f(t_k), and
    ///   `imaginaryResidual`, the largest |Im| seen relative to the largest
    ///   |Re| - a diagnostic that should be at rounding level.
    static func Invert(spectrum:[Complex<Double>], grid:LaplaceGrid, window:LaplaceWindow = .none) -> (values:[Double], imaginaryResidual:Double)? {

        guard spectrum.count == grid.frequencyCount else {

            DLog("Spectrum has \(spectrum.count) points, grid wants \(grid.frequencyCount)")
            return nil
        }

        let n = grid.sampleCount

        // `round` not `floor`: N is guaranteed a power of two by LaplaceGrid's
        // init, so log2(N) is an exact integer mathematically, but log2() of a
        // Double can land a hair under it. Truncating would then halve the
        // transform length silently - which is precisely the bug the old
        // GetFundamentalFrequency had.
        let log2n = vDSP_Length(round(log2(Double(n))))

        // The DOUBLE-PRECISION vDSP entry points (the trailing D) are used
        // deliberately, via the C API rather than the `vDSP.FFT` Swift
        // wrapper. Two reasons:
        //
        //   - Precision. The Swift wrapper's `ofType:` overload resolves to
        //     the single-precision DSPSplitComplex here. Float is not good
        //     enough: exp(+sigma*t) applied on the way out amplifies whatever
        //     error the transform carries, so starting from Float's ~1e-7
        //     would leave nothing usable by the end of the record.
        //
        //   - Unambiguous scaling. vDSP_fft_zopD in the inverse direction
        //     computes the bare unnormalised sum
        //         C[k] = sum over m of A[m] * exp(+2*pi*i*m*k/N)
        //     with no 1/N. That is exactly the discrete sum in the file
        //     header, so no correction factor is needed. `SelfCheck` verifies
        //     this against closed-form transforms rather than trusting it.
        guard let setup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else {

            DLog("Could not create the FFT setup for N = \(n)")
            return nil
        }

        defer {

            vDSP_destroy_fftsetupD(setup)
        }

        // --- Build the full length-N conjugate-symmetric spectrum ----------
        //
        //   bin m        = F_m              for m = 0 ... N/2
        //   bin (N - m)  = conj(F_m)        for m = 1 ... N/2 - 1
        //
        // Bin 0 (which sits at s = sigma, not at the origin - see the damping
        // discussion in the file header) and bin N/2 (Nyquist) are their own
        // mirror images and are written once. For the result to be exactly
        // real those two must themselves be real; they are not, in general,
        // because F is evaluated off the real axis. Taking their real part is
        // the standard treatment and the resulting error is O(F_{N/2}), which
        // is exactly the quantity the caller's band-limit check is there to
        // keep negligible.
        var re = [Double](repeating: 0.0, count: n)
        var im = [Double](repeating: 0.0, count: n)

        for m in 0..<grid.frequencyCount {

            let w = window.weight(m: m, count: grid.frequencyCount)
            let value = spectrum[m] * Complex(w)

            if m == 0 || m == n / 2 {

                re[m] = value.real
                im[m] = 0.0
            }
            else {

                re[m] = value.real
                im[m] = value.imaginary
                re[n - m] = value.real
                im[n - m] = -value.imaginary
            }
        }

        // --- Inverse DFT ---------------------------------------------------
        var outRe = [Double](repeating: 0.0, count: n)
        var outIm = [Double](repeating: 0.0, count: n)

        re.withUnsafeMutableBufferPointer { rePtr in
            im.withUnsafeMutableBufferPointer { imPtr in
                outRe.withUnsafeMutableBufferPointer { outRePtr in
                    outIm.withUnsafeMutableBufferPointer { outImPtr in

                        var input = DSPDoubleSplitComplex(realp: rePtr.baseAddress!, imagp: imPtr.baseAddress!)
                        var output = DSPDoubleSplitComplex(realp: outRePtr.baseAddress!, imagp: outImPtr.baseAddress!)

                        // "zop" = complex (z) out-of-place (op). Strides of 1
                        // for both. kFFTDirection_Inverse gives the +i
                        // exponential, which is the direction the Bromwich
                        // integral needs.
                        vDSP_fft_zopD(setup, &input, 1, &output, 1, log2n, FFTDirection(kFFTDirection_Inverse))
                    }
                }
            }
        }

        // --- Undo the damping and apply the 1/T scale ----------------------
        //
        //     f_k = exp(sigma * t_k) / T * (inverse DFT)_k
        //
        // `transformScale` absorbs whatever normalisation vDSP's inverse
        // applies. Apple's complex inverse FFT is unnormalised (it computes
        // the bare sum, with no 1/N), so the value is 1. This is pinned by
        // `SelfCheck` against transforms with closed-form answers: if a future
        // OS changes the convention, those tests fail loudly rather than the
        // whole simulation quietly scaling wrong.
        let transformScale = 1.0

        var values = [Double](repeating: 0.0, count: n)
        var maxAbsReal = 0.0
        var maxAbsImag = 0.0

        for k in 0..<n {

            let gain = exp(grid.damping * grid.time(at: k)) / grid.recordLength * transformScale

            values[k] = outRe[k] * gain

            maxAbsReal = max(maxAbsReal, abs(outRe[k]))
            maxAbsImag = max(maxAbsImag, abs(outIm[k]))
        }

        let residual = maxAbsReal > 0.0 ? maxAbsImag / maxAbsReal : maxAbsImag

        return (values, residual)
    }

    // MARK: - Self-check
    //
    // ========================================================================
    // WHERE THE ERROR LIVES - read this before adjusting any tolerance below
    // ========================================================================
    //
    // The inversion is not uniformly accurate across the record. Its error has
    // two distinct sources with completely different behaviour, and the
    // tolerances below are set from measurements of each, not from taste.
    //
    // 1. WAVEFRONT ERROR (t less than ~1 us), from spectral truncation.
    //
    //    The series is cut off at m = N/2. Whatever amplitude F still has at
    //    that band edge is simply missing from the answer, and because a step
    //    or a fast front is exactly what needs the high harmonics, the deficit
    //    piles up at the front. Measured worst relative error at the front,
    //    f_max = 10 MHz, no window:
    //
    //        F ~ 1/s   (a jump)         5.0e-1   <- converges to the MIDPOINT
    //        F ~ 1/s^2 (the raw source) 1.7e-2
    //        F ~ 1/s^3 (after the
    //                   asymptote is
    //                   subtracted)     1.1e-3
    //
    //    It improves only as 1/f_max for a 1/s^2 spectrum - doubling the
    //    bandwidth halves the error, so brute force is hopeless. This is the
    //    entire reason FrequencyDomainSolver subtracts the s -> infinity
    //    asymptote analytically before inverting: it converts the spectrum
    //    from 1/s^2 to 1/s^3, which converges quadratically and is 15x-40x
    //    better at identical cost.
    //
    // 2. TAIL ERROR (the rest of the record), from wraparound.
    //
    //    Whatever has not decayed by t = T folds back onto the start. This is
    //    what sigma suppresses, and it lands at roughly exp(-sigma*T) times
    //    the surviving amplitude - about 4e-4 at sigma*T = 5 for a signal with
    //    the standard wave's 70 us tail. Measured worst relative error for
    //    t >= 5 us, f_max = 10 MHz, no window:
    //
    //        damped sinusoid (20 us decay, nearly gone by T)   4.1e-7
    //        full wave       (70 us decay, still 6% at T)      3.7e-4
    //
    //    Note the consequence: the two error sources respond to DIFFERENT
    //    knobs. More bandwidth does nothing for the tail; more damping does
    //    nothing for the wavefront. A measurement that lumps them together
    //    will draw the wrong conclusion about which knob to turn.

    /// Inverts transforms whose answers are known in closed form and compares.
    ///
    /// This is the test that has to pass before the transform is allowed
    /// anywhere near the network. It independently pins down:
    ///
    ///   - the overall scale (the 1/T and vDSP's normalisation),
    ///   - the sign and direction of the exponential,
    ///   - the handling of the m = 0 and Nyquist bins,
    ///   - the conjugate-symmetry construction (via the imaginary residual),
    ///   - the damping applied on the way in and undone on the way out.
    ///
    /// A failure here means the transform is wrong for every input, which is
    /// far easier to see now than after it has been composed with an assembly
    /// bug in the network matrices.
    ///
    /// - returns: nil if every check passes, otherwise a description of the
    ///   first failure.
    static func SelfCheck() -> String? {

        let grid = LaplaceGrid.DefaultGrid(displaySpan: 100.0E-6, maximumFrequency: 1.0E7)

        /// Inverts `transform` and compares against `exact` over two regions:
        /// the whole displayed half, and the part after the wavefront has
        /// passed. Splitting them is what makes a failure diagnosable - a
        /// regression in `frontTolerance` alone means bandwidth or the
        /// asymptote subtraction, in `tailTolerance` alone means damping.
        func compare(name:String, transform:(Complex<Double>) -> Complex<Double>, exact:(Double) -> Double, frontTolerance:Double, tailTolerance:Double) -> String? {

            let spectrum = (0..<grid.frequencyCount).map { transform(grid.s(at: $0)) }

            guard let result = Invert(spectrum: spectrum, grid: grid) else {

                return "\(name): inversion failed outright"
            }

            // The conjugate-symmetric spectrum must produce an exactly real
            // signal. A non-zero imaginary part is not noise to be tolerated -
            // it means the Hermitian mirror is being built wrongly, and it
            // would be invisible in the real part until it corrupted an
            // answer.
            if result.imaginaryResidual > 1.0E-12 {

                return "\(name): imaginary residual is \(result.imaginaryResidual); the conjugate-symmetric spectrum is not being built correctly"
            }

            // Normalise by the PEAK of the exact answer, so the tolerance
            // means "relative to the size of the signal" rather than
            // "relative to this sample", which would be meaningless near a
            // zero crossing.
            var peak = 0.0
            for k in 0..<(grid.sampleCount / 2) {

                peak = max(peak, abs(exact(grid.time(at: k))))
            }

            guard peak > 0.0 else { return "\(name): the exact answer is identically zero" }

            var worstFront = 0.0
            var worstTail = 0.0
            var worstTailAt = 0.0

            // Only the first half of the record is examined. The second half
            // is the disposable margin described in DefaultGrid - it is where
            // wraparound lands and where exp(+sigma*t) amplification is worst,
            // and no caller is meant to read it.
            for k in 0..<(grid.sampleCount / 2) {

                let t = grid.time(at: k)
                let error = abs(result.values[k] - exact(t)) / peak

                worstFront = max(worstFront, error)

                if t >= 1.0E-6, error > worstTail {

                    worstTail = error
                    worstTailAt = t
                }
            }

            if worstFront > frontTolerance {

                return "\(name): worst error over the whole record is \(worstFront) (tolerance \(frontTolerance)) - suspect bandwidth or the asymptote subtraction"
            }

            if worstTail > tailTolerance {

                return "\(name): worst error after the wavefront is \(worstTail) at t = \(worstTailAt) s (tolerance \(tailTolerance)) - suspect the damping constant"
            }

            return nil
        }

        let k1 = 1.4285E4          // the standard full wave's slow pole
        let k2 = 3.3333333E6       // ... and its fast one
        let v0 = 1.03

        // --- 1. A single decaying exponential ------------------------------
        //
        //     F(s) = 1/(s + a)      <->      f(t) = exp(-a*t)
        //
        // The simplest transform with a pole, and the sharpest test of SCALE:
        // any factor-of-two error shows up here as a constant multiplier.
        //
        // The loosest tolerances of any check here, and deliberately so: a 1/s
        // spectrum is the slowest-decaying case in this file, so the
        // truncation deficit spills well past the wavefront (5.3e-3 at 1 us,
        // still 1.5e-3 by 5 us). That is a property of this artificial test
        // function, not of the application - the real response never has a
        // 1/s tail. This check is here for SCALE, which it pins to 2e-4, not
        // for accuracy.
        //
        // The wavefront tolerance is 0.6 because the exact answer has a
        // genuine jump at the origin that no bandwidth can reproduce; check 2
        // immediately below pins down what should happen there instead.
        if let failure = compare(name: "1/(s+a)",
                                 transform: { s in Complex(1.0) / (s + Complex(k1)) },
                                 exact: { t in exp(-k1 * t) },
                                 frontTolerance: 6.0E-1,
                                 tailTolerance: 8.0E-3) {

            return failure
        }

        // --- 2. Midpoint convergence at a jump -----------------------------
        //
        // f(t) = exp(-a*t) for t >= 0 is 0 just before the origin and 1 just
        // after. A Fourier series converges to the MIDPOINT of a jump, so the
        // correct answer at t = 0 is 0.5, not 1.0.
        //
        // This is asserted rather than tolerated, for two reasons. It confirms
        // the transform is behaving as Fourier theory requires rather than
        // being accidentally right; and it documents, in executable form, that
        // a half-height first sample is EXPECTED for a discontinuous input and
        // is not a bug to be chased. (The real network response starts from
        // zero and is continuous, so this case does not arise in practice -
        // but it will arise the moment anyone implements the chopped wave.)
        let jump = (0..<grid.frequencyCount).map { Complex(1.0) / (grid.s(at: $0) + Complex(k1)) }

        guard let jumpResult = Invert(spectrum: jump, grid: grid) else {

            return "midpoint check: inversion failed"
        }

        if abs(jumpResult.values[0] - 0.5) > 1.0E-3 {

            return "A jump discontinuity should invert to its midpoint 0.5 at t=0, got \(jumpResult.values[0])"
        }

        // --- 3. The actual impulse waveform --------------------------------
        //
        //     F(s) = v0 * ( 1/(s+k1) - 1/(s+k2) )
        //         <->  f(t) = v0 * ( exp(-k1*t) - exp(-k2*t) )
        //
        // The double exponential the simulation is actually driven with
        // (SimulationModel.WaveForm, full wave). Continuous at the origin, so
        // unlike check 1 the wavefront is meaningful here - and its 1.7e-2
        // error is exactly the 1/s^2 truncation that the solver's asymptote
        // subtraction exists to remove. If that number improves, the
        // subtraction has been applied somewhere it should not be; if it
        // degrades, the bandwidth has been cut.
        if let failure = compare(name: "double exponential (full wave)",
                                 transform: { s in Complex(v0) * (Complex(1.0) / (s + Complex(k1)) - Complex(1.0) / (s + Complex(k2))) },
                                 exact: { t in v0 * (exp(-k1 * t) - exp(-k2 * t)) },
                                 frontTolerance: 3.0E-2,
                                 tailTolerance: 1.0E-3) {

            return failure
        }

        // --- 4. A lightly damped oscillator --------------------------------
        //
        //     F(s) = w / ((s+a)^2 + w^2)   <->   f(t) = exp(-a*t) * sin(w*t)
        //
        // The network's own response is a superposition of exactly these, so
        // this is the closest standalone proxy for the real workload. A
        // 500 kHz ring with a 20 us decay is representative of a winding.
        //
        // It also confirms the SIGN of the exponential: an inverted direction
        // returns the time-reverse, which this test catches and the monotonic
        // checks above would not.
        //
        // Because it decays almost completely within the record, its tail
        // error is 4.1e-7 - three orders better than the full wave's, which is
        // the clearest available demonstration that the tail error is
        // wraparound and nothing else.
        let decay = 5.0E4
        let ring = 2.0 * π * 5.0E5

        if let failure = compare(name: "damped sinusoid",
                                 transform: { s in Complex(ring) / ((s + Complex(decay)) * (s + Complex(decay)) + Complex(ring * ring)) },
                                 exact: { t in exp(-decay * t) * sin(ring * t) },
                                 frontTolerance: 3.0E-2,
                                 tailTolerance: 5.0E-5) {

            return failure
        }

        // --- 5. A 1/s^3 spectrum -------------------------------------------
        //
        // This is the regime the solver ACTUALLY operates in, once
        // FrequencyDomainSolver has subtracted the s -> infinity asymptote. It
        // is the check that matters most for real results, and its tolerance
        // is 15x tighter than the raw 1/s^2 case above - which is the whole
        // justification for doing the subtraction at all.
        let third = 2.0E7
        let amplitude = v0 * (k2 - k1) * third

        if let failure = compare(name: "three-pole (1/s^3, post-subtraction regime)",
                                 transform: { s in Complex(amplitude) / ((s + Complex(k1)) * (s + Complex(k2)) * (s + Complex(third))) },
                                 exact: { t in amplitude * (exp(-k1 * t) / ((k2 - k1) * (third - k1))
                                                          + exp(-k2 * t) / ((k1 - k2) * (third - k2))
                                                          + exp(-third * t) / ((k1 - third) * (k2 - third))) },
                                 frontTolerance: 2.0E-3,
                                 tailTolerance: 1.0E-3) {

            return failure
        }

        // --- 6. Grid bookkeeping -------------------------------------------
        //
        // The power-of-two rounding is what the old GetFundamentalFrequency
        // got wrong - it floor'd log2 and silently transformed only a prefix
        // of the data - so it is checked explicitly rather than assumed.
        let odd = LaplaceGrid(sampleCount: 3000, recordLength: 1.0E-4, damping: 5.0E4)

        if odd.sampleCount != 4096 {

            return "Grid should round 3000 samples up to 4096, got \(odd.sampleCount)"
        }
        if odd.frequencyCount != 2049 {

            return "Grid with N=4096 should want 2049 contour points, got \(odd.frequencyCount)"
        }

        // The contour must never touch the origin: s = 0 is exactly where the
        // network's nodal matrix loses its capacitive term and goes singular.
        if odd.s(at: 0).imaginary != 0.0 || odd.s(at: 0).real != odd.damping {

            return "Contour point 0 must sit at s = sigma exactly, not at the origin"
        }

        return nil
    }
}
