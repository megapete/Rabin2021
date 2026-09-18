//
//  PchMatrix.swift
//  PchFiniteElement2D
//
//  Created by Peter Huber on 2023-09-28.
//

// Another version of the (in)famous "Peter Huber Matrix Class". The motivation for rewriting this (again) is the fact that in 2023, Apple "upgraded" their implementation of Blas, LAPACK, etc, and deprecated a bunch of the older calls (that I used to use). They also (for some reason) do not actually DEFINE any complex types anymore. I have therefore decided to write the class anew (using some of the coding techniques that I found in the Apple-written sample project "Accelerate-Linear-Solvers"). This class will implement solvers for various matrix types (including, eventually, Apple's sparse-matrix solver). I have decided not to implement "float" or "complex float" (this is 2023 for crying out loud), so only "double" and "complex double" are available (this may change if I see a need in the future). Compiling this file requires that the parent project set the following Preprocessor Macros (in Build Settings - Apple Clang - Preprocessing): ACCELERATE_NEW_LAPACK=1 and ACCELERATE_LAPACK_ILP64=1. It also requires that the Swift-Numerics package be installed.

// As of Nov. 30, 2023, sparse matrices are implemented but only in "general" (Apple calls them "ordinary") matrices (ie: not symmetric, not triangular, etc.). For now, the matrix itself is stored in "Coordinate" form (see the example in the Apple documentation for SparseFactor(_:_:_:_:) of how this is implemented). It is converted directly before being used when solving systems. Apple only offers up a "Double" version for sparse matrices, which means I will have to roll my own Complex types, but that means matrices where each entry actually requires 4 elements to define. This is a "future" project.

// As of this writing, the option to save factorizations of Sparse matrices is not actually supported (the SolveSparse() routine ignores the 'overwriteA' parameter).

// As of October 2023, the updated LAPACK and BLAS from Apple does not actually define complex or double-complex types (actually, it does not "completely" define them in the headers), which means that calling any routine that takes a pointer to a complex struct actually asks for a "OpaquePointer" (which is about as basic a pointer as you can get). Since most of the low-level pointer types in Swift do not have a guaranteed lifetime (ie: the stable of "Unsafe" pointer types), it is necessary to use the closure-using "with...Pointer" calls. 

// **NOTE** It is entirely possible (probable, even) that Apple will eventually fix this OpaquePointer nonsense and use an actually-defined type (hopefully the swift-numerics Complex class, which is what I have now adopted) at which time all of the complex functions will need to be rewritten (sigh).

// I give an example here in case I ever need to know what I did here for some future project:

/* For arrays, use 'withUnsafeBufferPointer' (or 'withUnsafeMutableBufferPointer', if the array will be changed), then typecast the resulting pointer's 'baseAdress' property to an OpaquePointer. Something like this:
 
    let myArray:[Double] = [1.0, 2.0, 3.0, 4.0]
    let myCount = myArray.count
 
    myArray.withUnsafeBufferPointer() { A in
 
        SpecialFunctionCall(OpaquePointer(A.baseAdress!), myCount)
    }
 
    NOTES: 1) If myArray will be changed by the function call, it should be declared as 'var' and 'withUnsafeMutableBufferPointer' should be used.
           2) Note that anything that refers to the original array (in this case, the 'count'), must be done OUTSIDE the closure, otherwise you'll get a compile-time error.
 
    For anything that is not an array, you'd do it like this:
 
    let myInt:Int
    
    withUnsafePointer(to: myInt) { A in
 
        SpecialFunctionCall(OpaquePointer(A))
    }
 
    Note that in either case, the "with...Pointer" calls can be nested, creating an Unsafe pointer for all parameters that may be need in the call (see any of the Complex function calls in this file for an example of this).
*/

import Foundation
import Accelerate
import ComplexModule

class PchMatrix:CustomStringConvertible, Equatable, Codable {
    
    var description: String {
        
        get {
            
            var result:String = ""
            
            for j in 0..<self.rows
            {
                result += "|"
                for i in 0..<self.columns
                {
                    if self.numType == .Double
                    {
                        if let number:Double = self[j, i] {
                            
                            result.append(String(format: " % 6.6f", number))
                        }
                    }
                    else
                    {
                        if let number:Complex = self[j, i] {
                            
                            result.append(String(format: " % 5.3f%+5.3fi", number.real, number.imaginary))
                        }
                    }
                }
                
                result += " |\n"
            }
            
            return result
        }
    }
    
    /// Return the CSV String of the matrix, the obvious intent being to save it is as a CSV file
    var csv:String {
        get {
            
            guard self.rows > 0 && self.columns > 0 else {
                
                return ""
            }
            
            var result:String = ","
            
            for i in 0..<self.columns {
                
                result.append("\(i),")
            }
            result += "\n"
            
            for j in 0..<self.rows
            {
                result.append("\(j),")
                for i in 0..<self.columns
                {
                    if self.numType == .Double
                    {
                        if let number:Double = self[j, i] {
                            
                            result.append(String(format: "%6.5E,", number))
                        }
                    }
                    else
                    {
                        if let number:Complex = self[j, i] {
                            
                            result.append(String(format: "%.6f%+.6fi,", number.real, number.imaginary))
                        }
                    }
                }
                
                // get rid of the last comma
                result.removeLast()
                result += "\n"
            }
            
            return result
        }
    }
    
    /// User-adjustable class property to define the precision to which two numbers are considered "equal".
    static var equalityPrecision:Double = 1.0E-8
    
    static func == (lhs: PchMatrix, rhs: PchMatrix) -> Bool {
        
        // check obvious stuff first
        guard lhs.matrixType == rhs.matrixType, lhs.numType == rhs.numType, lhs.rows == rhs.rows, lhs.columns == rhs.columns, lhs.factorizationType == rhs.factorizationType, lhs.buffPtr.count == rhs.buffPtr.count else {
            
            return false
        }
        
        for i in 0..<lhs.buffPtr.count {
            
            let relativeDiff = fabs((lhs.buffPtr[i] - rhs.buffPtr[i]) / lhs.buffPtr[i])
            
            if relativeDiff > equalityPrecision {
                
                return false
            }
        }
        
        return true
    }
    
    /// Different matrix types that we accept (this will likely grow in the future)
    enum MatrixType:Int {
        case general
        case sparse
        case diagonal
        case symmetric
        case positiveDefinite
    }
    
    let matrixType:MatrixType
    
    /// The two number types that we allow
    enum NumberType:Int {
        case Double
        case Complex
    }
    
    let numType:NumberType
    
    /// The factorization (if any) that the matrix currently in memory has had applied
    enum FactorizationType:Int {
        case none
        case Cholesky
        case LU
        case QR
    }
    
    private var factorizationStore:FactorizationType = .none
    
    var factorizationType:FactorizationType {
        
        get {
            
            return factorizationStore
        }
        
        set {
            
            if newValue == .Cholesky && matrixType == .positiveDefinite {
                
                    factorizationStore = newValue
                    return
            }
            
            // default
            factorizationStore = newValue
        }
    }
    
    /// The buffer that holds the matrix
    private var buffPtr:[Double]
    
    /// Sparse matrix stuff
    struct SparseIndexKey:Hashable, Codable {
        
        let rowIndex:Int
        let colIndex:Int
    }
    /// Dictionary for sparse matrices
    private var sparseDict:[SparseIndexKey:Double] = [:]
    
    /// Storage for the IPIV array when a matrix is stored as its LU-decomposition
    var ipivBuff:[__LAPACK_int] = []
    
    /// The number of rows in the matrix
    let rows:Int
    /// The number of columns in the matrix
    let columns:Int
    
    /// Required enum to make this class Codable
    enum CodingKeys: CodingKey {
        
        case matrixType
        case numType
        case factType
        case rows
        case columns
        case buffer
        case ipiv
        case sparseDict
    }
    
    var isVector:Bool {
        
        get {
            
            return columns == 1
        }
    }
    
    /// The designated initializer for the class. Note that the rows and columns must be passed as UInts (to enforce >0 rules at the compiler level) but are immediately converted to Ints internally to keep from having to wrap things in Int()
    init(matrixType:MatrixType = .general, numType:NumberType, rows:UInt, columns:UInt) {
        
        self.numType = numType
        self.matrixType = matrixType
        
        // force vectors to have a single column instead of a single row
        if rows == 1 {
            self.columns = 1
            self.rows = matrixType == .diagonal ? 1 : Int(columns)
        }
        else {
            self.rows = Int(rows)
            self.columns = matrixType == .diagonal ? self.rows : Int(columns) // force columns = rows for diagonal
        }
        
        var requiredMemoryCapacity = self.rows // diagonal
        if matrixType == .general {
            
            requiredMemoryCapacity *= self.columns
        }
        else if matrixType == .sparse {
            
            requiredMemoryCapacity = 0
        }
        // else if 'other matrix type'
        
        // Complex needs twice the space
        if numType == .Complex {
            
            requiredMemoryCapacity *= 2
        }
        
        self.buffPtr = Array(repeating: 0.0, count: requiredMemoryCapacity)
    }
    
    /// Decoding initializer
    required init(from decoder: Decoder) throws {
        
        do {
            
            let storedValues = try decoder.container(keyedBy: CodingKeys.self)
            
            let storedMatrixType = try storedValues.decode(Int.self, forKey: .matrixType)
            self.matrixType = MatrixType(rawValue: storedMatrixType)!
            
            let storedType = try storedValues.decode(Int.self, forKey: .numType)
            self.numType = NumberType(rawValue: storedType)!
            
            let storedFactType = try storedValues.decode(Int.self, forKey: .factType)
            self.factorizationStore = FactorizationType(rawValue: storedFactType)!
            
            self.ipivBuff = try storedValues.decode([__LAPACK_int].self, forKey: .ipiv)
            
            self.rows = try storedValues.decode(Int.self, forKey: .rows)
            self.columns = try storedValues.decode(Int.self, forKey: .columns)
            
            self.sparseDict = try storedValues.decode([SparseIndexKey:Double].self, forKey: .sparseDict)
            
            self.buffPtr = try storedValues.decode([Double].self, forKey: .buffer)
        }
        catch {
            
            throw error
        }
    }
    
    func encode(to encoder: Encoder) throws {
        
        do {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.matrixType.rawValue, forKey: .matrixType)
            try container.encode(self.numType.rawValue, forKey: .numType)
            try container.encode(self.factorizationType.rawValue, forKey: .factType)
            try container.encode(self.rows, forKey: .rows)
            try container.encode(self.columns, forKey: .columns)
            try container.encode(self.ipivBuff, forKey: .ipiv)
            try container.encode(self.buffPtr, forKey: .buffer)
            try container.encode(self.sparseDict, forKey: .sparseDict)
        }
        catch {
            
            throw error
        }
    }
    
    
    func CheckBounds(row:Int, column:Int) -> Bool {
        
        return row >= 0 && row < rows && column >= 0 && column < columns
    }
    
    subscript(row:Int, column:Int) -> Double? {
        
        get {
            
            guard CheckBounds(row: row, column: column) else {
                
                ALog("Index out of bounds!")
                return nil
            }
            
            if numType == .Double {
                
                if matrixType == .diagonal {
                    
                    if (row == column) {
                        
                        return buffPtr[row]
                    }
                    else {
                        
                        return 0.0
                    }
                }
                else if matrixType == .sparse {
                    
                    let spKey = SparseIndexKey(rowIndex: row, colIndex: column)
                    if let spValue = self.sparseDict[spKey] {
                        
                        return spValue
                    }
                    
                    return 0.0
                }
                else if matrixType == .general {
                    
                    return buffPtr[column * self.rows + row]
                }
                else {
                    
                    ALog("Unknown matrix type (impossible error)")
                    return nil
                }
            }
            
            ALog("Type mismatch!")
            return nil
        }
        
        set {
            
            guard CheckBounds(row: row, column: column) else {
                
                ALog("Index out of bounds!")
                return
            }
            
            guard let actualValue = newValue else {
                
                DLog("Trying to assign nil - ignoring")
                return
            }
            
            if self.numType == .Double {
                
                if self.matrixType == .diagonal {
                    
                    if (row != column)
                    {
                        DLog("Unsettable index for diagonal matrix - ignoring")
                        return
                    }
                    
                    buffPtr[row] = actualValue
                }
                else if matrixType == .sparse {
                    
                    let spKey = SparseIndexKey(rowIndex: row, colIndex: column)
                    self.sparseDict[spKey] = actualValue
                }
                else if matrixType == .general {
                    
                    buffPtr[(column * self.rows) + row] = actualValue
                }
                else {
                    
                    ALog("Unknown matrix type (impossible error)")
                    return
                }
            }
            else {
                
                ALog("Type mismatch")
            }
            
            return
        }
    }
    
    subscript(row:Int, column:Int) -> Complex<Double>? {
        
        get {
            
            guard CheckBounds(row: row, column: column) else {
                
                ALog("Index out of bounds!")
                return nil
            }
            
            if numType == .Complex {
                
                if matrixType == .diagonal {
                    
                    if (row == column) {
                        
                        return Complex(buffPtr[row * 2], buffPtr[row * 2 + 1])
                    }
                    else {
                        
                        return Complex.zero
                    }
                }
                else if matrixType == .sparse {
                    
                    ALog("Unimplemented matrix type!")
                    return nil
                }
                else if matrixType == .general {
                    
                    let real = buffPtr[(column * self.rows + row) * 2]
                    let imag = buffPtr[(column * self.rows + row) * 2 + 1]
                    return Complex(real, imag)
                }
                else {
                    
                    ALog("Unknown matrix type (impossible error)")
                    return nil
                }
            }
            
            else {
                
                ALog("Type mismatch!")
            }
            
            return nil
        }
        
        set {
            
            guard CheckBounds(row: row, column: column) else {
                
                ALog("Index out of bounds!")
                return
            }
            
            guard let actualValue = newValue else {
                
                DLog("Trying to assign nil - ignoring")
                return
            }
            
            if self.numType == .Complex {
                
                if self.matrixType == .diagonal {
                    
                    if (row != column)
                    {
                        DLog("Unsettable index for diagonal matrix - ignoring")
                        return
                    }
                    
                    buffPtr[row * 2] = actualValue.real
                    buffPtr[row * 2 + 1] = actualValue.imaginary
                }
                else if matrixType == .sparse {
                    
                    ALog("Unimplemented matrix type!")
                    return
                }
                else if matrixType == .general {
                    
                    buffPtr[(column * self.rows + row) * 2] = actualValue.real
                    buffPtr[(column * self.rows + row) * 2 + 1] = actualValue.imaginary
                }
                else {
                    
                    ALog("Unknown matrix type (impossible error)")
                    return
                }
            }
            else {
                
                ALog("Type mismatch")
            }
            
            return
        }
    }
    
    /// Copy constructor.
    /// - Parameter srcMatrix: The matrix to copy
    init(srcMatrix:PchMatrix)
    {
        self.numType = srcMatrix.numType
        self.rows = srcMatrix.rows
        self.columns = srcMatrix.columns
        self.factorizationStore = srcMatrix.factorizationType
        self.ipivBuff = srcMatrix.ipivBuff
        self.matrixType = srcMatrix.matrixType
        self.sparseDict = srcMatrix.sparseDict
        self.buffPtr = srcMatrix.buffPtr
    }
    
    /// Convert a matrix numType to Complex (if self is already Complex, return a copy of self)
    func asComplexMatrix() -> PchMatrix {
        
        if matrixType == .sparse {
            
            ALog("Uh-uh!! Not implemented for sparse matrices yet!")
        }
        
        if numType == .Complex {
            
            return PchMatrix(srcMatrix: self)
        }
        
        let result = PchMatrix(matrixType: self.matrixType, numType: .Complex, rows: UInt(self.rows), columns: UInt(self.columns))
        
        for nextReal in self.buffPtr {
            
            result.buffPtr.append(nextReal)
            result.buffPtr.append(0.0)
        }
        
        return result
    }
    
    /// Return a general matrix from self. If self is already a general matrix, a deep copy is made instead
    func asGeneralMatrix() -> PchMatrix? {
        
        if matrixType == .general {
            
            return PchMatrix(srcMatrix: self)
        }
        
        let result = PchMatrix(matrixType: .general, numType: self.numType, rows: UInt(self.rows), columns: UInt(self.columns))
        
        for i in 0..<self.rows {
            
            for j in 0..<self.columns {
                
                if numType == .Double {
                    
                    if let value:Double = self[i, j] {
                        
                        result[i, j] = value
                    }
                    else {
                        
                        ALog("Could not get value")
                        return nil
                    }
                }
                else {
                    
                    if let value:Complex<Double> = self[i, j] {
                        
                        result[i, j] = value
                    }
                    else {
                        
                        ALog("Could not get Complex value")
                        return nil
                    }
                }
            }
        }
        
        return result
    }
    
    /// Multiply a matrix by a scalar (Double), keeping the same numType for the resulting matrix
    static func * (scalar:Double, matrix:PchMatrix) -> PchMatrix {
        
        if matrix.numType == .Complex {
            
            return Complex(scalar, 0) * matrix
        }
        
        if matrix.isVector && matrix.matrixType == .general {
            
            // This is written to figure out how to use .withUnsafeMutableBufferPointer
            var bufferCpy = matrix.buffPtr
            let vecCount = __LAPACK_int(bufferCpy.count)
            bufferCpy.withUnsafeMutableBufferPointer { X in
            
                cblas_dscal(vecCount, scalar, X.baseAddress, __LAPACK_int(1))
            }
            
            let result = PchMatrix(matrixType: matrix.matrixType, numType: .Double, rows: UInt(matrix.rows), columns: 1)
            result.buffPtr = bufferCpy
            return result
        }
        
        let result = PchMatrix(matrixType: matrix.matrixType, numType: matrix.numType, rows: UInt(matrix.rows), columns: UInt(matrix.columns))
        
        for nextDouble in matrix.buffPtr {
            
            result.buffPtr.append(scalar * nextDouble)
        }
        
        return result
    }
    
    /// Allow a user to specify the scalar after the matrix (same result)
    static func * (matrix:PchMatrix, scalar:Double) -> PchMatrix {
        
        return scalar * matrix
    }
    
    static func *= (matrix:inout PchMatrix, scalar:Double) {
        
        matrix = scalar * matrix
    }
    
    /// Note: if 'matrix' is 'Double', the function works but the new matrix will be converted to 'Complex'
    static func * (scalar:Complex<Double>, matrix:PchMatrix) -> PchMatrix {
        
        let result = PchMatrix(matrixType: matrix.matrixType, numType: .Complex, rows: UInt(matrix.rows), columns: UInt(matrix.columns))
        
        let indexMultiplier = matrix.numType == .Double ? 1 : 2
        let numEntriesInBuffer = matrix.buffPtr.count / indexMultiplier
        
        for i in 0..<numEntriesInBuffer {
            
            let realPart = matrix.buffPtr[i * indexMultiplier]
            let imagPart = matrix.numType == .Double ? 0.0 : matrix.buffPtr[i * indexMultiplier + 1]
            
            let newValue:Complex<Double> = scalar * Complex(realPart, imagPart)
            
            result.buffPtr.append(newValue.real)
            result.buffPtr.append(newValue.imaginary)
        }
        
        return result
    }
    
    /// Allow a user to specify the scalar after the matrix (same result)
    static func * (matrix:PchMatrix, scalar:Complex<Double>) -> PchMatrix {
        
        return scalar * matrix
    }
    
    static func *= (matrix:inout PchMatrix, scalar:Complex<Double>) {
        
        matrix = scalar * matrix
    }
    
    /// A x B = C : Multiply two matrices (or vectors). If either of the two matrices is of Complex type, the returned matrix is also Complex. If the dimensions of the two matrices are incompatible, this will return nil
    static func * (lhs:PchMatrix, rhs:PchMatrix) -> PchMatrix? {
        
        if lhs.columns != rhs.rows {
            
            DLog("Incompatible dimensions!")
            return nil
        }
        
        let resultNumType:PchMatrix.NumberType = lhs.numType == .Complex || rhs.numType == .Complex ? .Complex : .Double
        
        // take care of the special case of AxB where A is a diagonal matrix and B is a vector
        if lhs.matrixType == .diagonal && rhs.isVector
        {
            let result = PchMatrix(matrixType: .diagonal, numType: resultNumType, rows: UInt(lhs.rows), columns: UInt(rhs.columns))
            
            if resultNumType == .Complex {
                
                let complexLHS = lhs.asComplexMatrix()
                let complexRHS = rhs.asComplexMatrix()
                
                for i in 0..<lhs.rows {
                    
                    guard let lhsEntry:Complex<Double> = complexLHS[i, i], let rhsEntry:Complex<Double> = complexRHS[i, 0] else {
                        
                        ALog("Could not get complex value(s)!")
                        return nil
                    }
                    
                    result[i, i] = lhsEntry * rhsEntry
                }
            }
            else {
                
                for i in 0..<lhs.rows {
                    
                    guard let lhsEntry:Double = lhs[i, i], let rhsEntry:Double = rhs[i, 0] else {
                        
                        ALog("Could not get real value(s)!")
                        return nil
                    }
                    
                    result[i, i] = lhsEntry * rhsEntry
                }
            }
            
            return result
        }
        
        // the matrix A isn't diagonal, create copies of both matrices (as general matrices) before proceeding
        guard let genLHS = lhs.asGeneralMatrix(), let genRHS = rhs.asGeneralMatrix() else {
            
            ALog("Could not convert to general matrix!")
            return nil
        }
        
        if resultNumType == .Double {
            
            if rhs.isVector {
                
                let a = genLHS.buffPtr
                let x = genRHS.buffPtr
                var y = x
                let m = __LAPACK_int(genLHS.rows)
                let lda = m
                let n = __LAPACK_int(genLHS.columns)
                let inc = __LAPACK_int(1)
                
                // call the cblas_* version of the function (easier to call)
                cblas_dgemv(CblasColMajor, CblasNoTrans, m, n, 1.0, a, lda, x, inc, 0.0, &y, inc)
                
                let result = PchMatrix(matrixType: .general, numType: .Double, rows: UInt(lhs.rows), columns: 1)
                result.buffPtr = y
                return result
            }
            else {
                
                let a = genLHS.buffPtr
                let b = genRHS.buffPtr
                var c:[Double] = Array(repeating: 0.0, count: genLHS.rows * genRHS.columns)
                let m = __LAPACK_int(genLHS.rows)
                let n = __LAPACK_int(genRHS.columns)
                let k = __LAPACK_int(genLHS.columns)
                let lda = m
                let ldb = k
                let ldc = m
                
                // call the cblas_* version of the function (easier to call)
                cblas_dgemm(CblasColMajor, CblasNoTrans, CblasNoTrans, m, n, k, 1.0, a, lda, b, ldb, 0.0, &c, ldc)
                
                let result = PchMatrix(matrixType: .general, numType: .Double, rows: UInt(lhs.rows), columns: UInt(rhs.columns))
                result.buffPtr = c
                return result
            }
        }
        
        // if we get here, we're doing a Complex result, so we need to use a considerably more "complex" method of calling the cblas_* functions (see the header of this file to see why Complex numbers are such a pain)
        let complexLHS = genLHS.asComplexMatrix()
        let complexRHS = genRHS.asComplexMatrix()
        
        if complexRHS.columns == 1 {
            
            // matrix-vector multiply
            
            // just copy the rhs buffer to get the correct size for Y
            var y = complexRHS.buffPtr
            let m = __LAPACK_int(complexLHS.rows)
            let lda = m
            let n = __LAPACK_int(complexLHS.columns)
            let inc = __LAPACK_int(1)
            let alpha:[Double] = [1.0, 0.0]
            let beta:[Double] = [0.0, 0.0]
            
            complexLHS.buffPtr.withUnsafeBufferPointer() { A in
                alpha.withUnsafeBufferPointer() { ALPHA in
                    beta.withUnsafeBufferPointer() { BETA in
                        complexRHS.buffPtr.withUnsafeBufferPointer() { X in
                            y.withUnsafeMutableBufferPointer() { Y in
                                
                                cblas_zgemv(CblasColMajor, CblasNoTrans, m, n, OpaquePointer(ALPHA.baseAddress!), OpaquePointer(A.baseAddress!), lda, OpaquePointer(X.baseAddress!), inc, OpaquePointer(BETA.baseAddress!), OpaquePointer(Y.baseAddress!), inc)
                            }
                        }
                    }
                }
            }
            
            let result = PchMatrix(matrixType: .general, numType: .Complex, rows: UInt(complexLHS.rows), columns: UInt(complexRHS.columns))
            result.buffPtr = y
            return result
        }
        else {
            
            // general matrix-matrix multiply
            
            var c:[Double] = Array(repeating: 0.0, count: complexLHS.rows * complexRHS.columns * 2)
            let m = __LAPACK_int(complexLHS.rows)
            let n = __LAPACK_int(complexRHS.columns)
            let k = __LAPACK_int(complexLHS.columns)
            let alpha:[Double] = [1.0, 0.0]
            let beta:[Double] = [0.0, 0.0]
            let lda = m
            let ldb = k
            let ldc = m
            
            complexLHS.buffPtr.withUnsafeBufferPointer() { A in
                complexRHS.buffPtr.withUnsafeBufferPointer() { B in
                    alpha.withUnsafeBufferPointer() { ALPHA in
                        beta.withUnsafeBufferPointer() { BETA in
                            c.withUnsafeMutableBufferPointer() { C in
                                
                                cblas_zgemm(CblasColMajor, CblasNoTrans, CblasNoTrans, m, n, k, OpaquePointer(ALPHA.baseAddress!), OpaquePointer(A.baseAddress!), lda, OpaquePointer(B.baseAddress!), ldb, OpaquePointer(BETA.baseAddress!), OpaquePointer(C.baseAddress!), ldc)
                            }
                        }
                    }
                }
            }
            
            
            let result = PchMatrix(matrixType: .general, numType: .Complex, rows: UInt(complexLHS.rows), columns: UInt(complexRHS.columns))
            result.buffPtr = c
            return result
        }
    }
    
    /// Solve the system of equations AX=B where A is 'self', a SPARSE matrix and X and B are dense vectors. If A is NOT a 'sparse' matrix, the call fails and returns nil. If A is not a square matrix, the call returns nil.
    /// - parameter B: A "general" type vector (single column). If B is not a vector, the call fails and returns nil
    /// - parameter overwriteA: A  Boolean to indicate that the A matrix should be overwritten with the LU factorization of A (for further computations). As of this writing, overwriting a sparse matrix with its factorization is not implemented (mostly because the factorization yields an opaque type that may or may not be compatible with the storage method of this class).
    /// - returns: The vector 'X' (the solution of the system)
    /// - note: At this time, Complex numbers are not supported for sparse matrices
    /// - note: Much of the sparse-related code in this function comes from the example for 
    func SolveSparse(B:PchMatrix, overwriteA:Bool = false) -> PchMatrix? {
        
        guard self.numType == .Double && B.numType == .Double else {
            
            DLog("Only Double number types are supported for sparse matrices!")
            return nil
        }
        
        guard self.matrixType == .sparse && B.matrixType == .general else {
            
            DLog("The A matrix must be 'sparse' type and the B matrix must be 'general' type!")
            return nil
        }
        
        guard self.rows == self.columns else {
            
            DLog("Matrix is not square!")
            return nil
        }
        
        guard B.isVector else {
            
            DLog("B matrix must be a vector")
            return nil
        }
        
        self.buffPtr = []
        var rowIndices:[Int32] = []
        var colIndices:[Int32] = []
        for (spKey, spValue) in self.sparseDict {
            
            rowIndices.append(Int32(spKey.rowIndex))
            colIndices.append(Int32(spKey.colIndex))
            self.buffPtr.append(spValue)
        }
        
        // Convert the buffer to the format expected by the Sparse routines
        // NOTE: Adapting sparse matrices for Complex types should use a strategy of declaring each Complex number as a 4-element "block" of Doubles in the call to SparseConvertFromCoordinate() which follows.
        let A = SparseConvertFromCoordinate(Int32(rows), Int32(columns), buffPtr.count, 1, SparseAttributes_t(), rowIndices, colIndices, buffPtr)
        
        // This comes straight from the example. Create the symbolic and numeric options using pretty much "default" values, then create the QR factorization
        let symbolicOptions = SparseSymbolicFactorOptions(control: SparseDefaultControl, orderMethod: SparseOrderDefault, order: nil, ignoreRowsAndColumns: nil, malloc: { malloc($0) }, free: { free($0) }, reportError: nil)
        let numericOptions = SparseNumericFactorOptions()
        let factorization = SparseFactor(SparseFactorizationQR, A, symbolicOptions, numericOptions)

        // My first ever (I think) use of the defer statement, which is actually a good idea
        defer {
            
            SparseCleanup(A)
            SparseCleanup(factorization)
        }
        
        var bValues = B.buffPtr
        
        bValues.withUnsafeMutableBufferPointer { bPtr in
            
            let xb = DenseVector_Double(count: Int32(B.buffPtr.count),
                                       data: bPtr.baseAddress!)
            
            SparseSolve(factorization, xb)
        }
        
        // Unimplemented (see the note in the description of the 'overwriteA' parameter in the Help for this function
        // if overwriteA {
            
        let result = PchMatrix(matrixType: .general, numType: .Double, rows: UInt(self.rows), columns: 1)
        result.buffPtr = bValues
        return result
    }
    
    /// Solve the system of equations AX=B where A is 'self', a general matrix and X and B are vectors. If A is NOT a 'general' matrix, the call fails and returns nil. If A is not a square matrix, the call returns nil
    /// - parameter B: A "general" type vector (single column). If B is not a vector, the call fails and returns nil
    /// - parameter overwriteA: A  Boolean to indicate that the A matrix should be overwritten with the LU factorization of A (for further computations). _This parameter is ignored if 'self' is a Double matrix and 'B' is a Complex vector. Also, if A is already factorized, this parameter is ignored._
    /// - returns: The vector 'X' (the solution of the system)
    /// - note: If either 'self' or 'B' is a Complex matrix, the non-Complex matrix (if any) will be converted to Complex before the routine runs and the returned vector (X) will be of Complex type. See the note regarding the overwriteA parameter above.
    func SolveGeneral(B:PchMatrix, overwriteA:Bool = false) -> PchMatrix? {
        
        guard self.matrixType == .general && B.matrixType == .general else {
            
            DLog("Matrix must be 'general' type!")
            return nil
        }
        
        guard self.rows == self.columns else {
            
            DLog("Matrix is not square!")
            return nil
        }
        
        guard B.isVector else {
            
            DLog("B matrix must be a vector")
            return nil
        }
        
        // figure out the NumberType we should use
        let solveNumType:NumberType = self.numType == .Complex || B.numType == .Complex ? .Complex : .Double
        
        // set the A-matrix NumberType
        guard let A:PchMatrix = self.numType != solveNumType ? (solveNumType == .Complex ? self.asComplexMatrix() : nil) : self else {
            
            DLog("Wow, something REALLY went wrong!")
            return nil
        }
        
        // Set the B-vector NumberType
        guard let BB:PchMatrix = B.numType != solveNumType ? (solveNumType == .Complex ? B.asComplexMatrix() : nil) : B else {
            
            DLog("Wow, something REALLY went wrong!")
            return nil
        }
        
        // In theory, at this point, both A and BB are matrices of the same number type. The actual function we will call depends on what that number type is and if the matrix is factorized...
        if solveNumType == .Double {
            
            if self.factorizationType == .LU {
                
                // use dgetrs_
                
                var Abuf = A.buffPtr
                var Bbuf = BB.buffPtr
                var ipiv:[__LAPACK_int] = Array(repeating: 0, count: A.rows)
                var info:__LAPACK_int = 0
                
                withUnsafePointer(to: Int8("N".utf8.first!)) { trans in
                    withUnsafePointer(to: __LAPACK_int(A.rows)) { n in
                        withUnsafePointer(to: __LAPACK_int(1)) { nrhs in
                            
                            dgetrs_(trans, n, nrhs, &Abuf, n, &ipiv, &Bbuf, n, &info)
                        }
                    }
                }
                
                if info < 0
                {
                    PCH_ErrorAlert(message: "DGETRS Error", info: "Illegal Argument #\(-info)")
                    return nil
                }
                else if info > 0
                {
                    PCH_ErrorAlert(message: "DGETRS Error", info: "The element U(\(info),\(info)) is exactly zero.")
                    return nil
                }
                
                let result = PchMatrix(matrixType: .general, numType: solveNumType, rows: UInt(self.rows), columns: 1)
                result.buffPtr = Bbuf
                return result
            }
            
            // No factorization, do it the long way (dgesv_)
            var Abuf = A.buffPtr
            var Bbuf = BB.buffPtr
            var ipiv:[__LAPACK_int] = Array(repeating: 0, count: A.rows)
            var info:__LAPACK_int = 0
            
            withUnsafePointer(to: __LAPACK_int(A.rows)) { n in
                withUnsafePointer(to: __LAPACK_int(1)) { nrhs in
                    
                    dgesv_(n, nrhs, &Abuf, n, &ipiv, &Bbuf, n, &info)
                }
            }
            
            if info < 0
            {
                PCH_ErrorAlert(message: "DGESV Error", info: "Illegal Argument #\(-info)")
                return nil
            }
            else if info > 0
            {
                PCH_ErrorAlert(message: "DGESV Error", info: "The element U(\(info),\(info)) is exactly zero.")
                return nil
            }
            
            if overwriteA && self.numType == solveNumType {
                
                self.buffPtr = Abuf
                self.factorizationType = .LU
                self.ipivBuff = ipiv
            }
            
            let result = PchMatrix(matrixType: .general, numType: solveNumType, rows: UInt(self.rows), columns: 1)
            result.buffPtr = Bbuf
            return result
        }
            
        else { // must be .Complex
            
            if self.factorizationType == .LU {
                
                // use zgetrs_
                
                var Bbuf = BB.buffPtr
                var ipiv:[__LAPACK_int] = Array(repeating: 0, count: A.rows)
                var info:__LAPACK_int = 0
                
                withUnsafePointer(to: Int8("N".utf8.first!)) { trans in
                    withUnsafePointer(to: __LAPACK_int(A.rows)) { n in
                        withUnsafePointer(to: __LAPACK_int(1)) { nrhs in
                            A.buffPtr.withUnsafeBufferPointer() { aBuf in
                                Bbuf.withUnsafeMutableBufferPointer() { bBuf in
                                    
                                    zgetrs_(trans, n, nrhs, OpaquePointer(aBuf.baseAddress!), n, &ipiv, OpaquePointer(bBuf.baseAddress!), n, &info)
                                }
                            }
                        }
                    }
                }
                
                if info < 0
                {
                    PCH_ErrorAlert(message: "ZGETRS Error", info: "Illegal Argument #\(-info)")
                    return nil
                }
                else if info > 0
                {
                    PCH_ErrorAlert(message: "ZGETRS Error", info: "The element U(\(info),\(info)) is exactly zero.")
                    return nil
                }
                
                let result = PchMatrix(matrixType: .general, numType: solveNumType, rows: UInt(self.rows), columns: 1)
                result.buffPtr = Bbuf
                return result
            }
            
            // No factorization, do it the long way (zgesv_)
            var Abuf = A.buffPtr
            var Bbuf = BB.buffPtr
            var ipiv:[__LAPACK_int] = Array(repeating: 0, count: A.rows)
            var info:__LAPACK_int = 0
            
            withUnsafePointer(to: __LAPACK_int(A.rows)) { n in
                withUnsafePointer(to: __LAPACK_int(1)) { nrhs in
                    Abuf.withUnsafeMutableBufferPointer() { aBuf in
                        Bbuf.withUnsafeMutableBufferPointer() { bBuf in
                            
                            zgesv_(n, nrhs, OpaquePointer(aBuf.baseAddress!), n, &ipiv, OpaquePointer(bBuf.baseAddress!), n, &info)
                        }
                    }
                }
            }
            
            if info < 0
            {
                PCH_ErrorAlert(message: "DGESV Error", info: "Illegal Argument #\(-info)")
                return nil
            }
            else if info > 0
            {
                PCH_ErrorAlert(message: "DGESV Error", info: "The element U(\(info),\(info)) is exactly zero.")
                return nil
            }
            
            if overwriteA && self.numType == solveNumType {
                
                self.buffPtr = Abuf
                self.factorizationType = .LU
                self.ipivBuff = ipiv
            }
            
            let result = PchMatrix(matrixType: .general, numType: solveNumType, rows: UInt(self.rows), columns: 1)
            result.buffPtr = Bbuf
            return result
        }
    }
    
    /// A routine to check whether a matrix is really positive-definite or not (inductance matrix is supposed to always be). The idea comes from this discussion: https://icl.cs.utk.edu/lapack-forum/viewtopic.php?f=2&t=3534. We need to try and perform a Cholesky factorization of the matrix (LAPACK routine DPOTRF). If the factorization is successfull, the matrix is positive definite.
    /// - note: If the matrix is already set as positive-definite, the routine simply returns true and ignores the 'overwriteExistingMatrix' parameter
    /// - note: If the matrix is diagonal, the matrix is positive-definite provided that every value on the diagonal (or the real part of every Complex value on the diagonal) is POSITIVE
    /// - Parameter overwriteExistingMatrix: If 'true', the function actually saves the Cholesky factorization by overwriting the existing buffer for this matrix
    /// - Returns: 'true' if the matrix is Positive Definite, otherwise 'false'
    func TestPositiveDefinite(overwriteExistingMatrix:Bool = false) -> Bool
    {
        // take care of some trivial possibilities first
        if self.matrixType == .positiveDefinite {
            
            // duh
            return true
        }
        
        guard self.TestForSymmetry() else
        {
            DLog("Matrix must be square and symmetric!")
            return false
        }
        
        // Diagonal matrices are positive definite iff all the entries (all the 'real' entries for Complex matices) on the diagonal are positive
        if self.matrixType == .diagonal {
            
            let strideVal:Int = self.numType == .Double ? 1 : 2
            for i in stride(from: 0, to: self.rows, by: strideVal) {
                
                if self.buffPtr[i] < 0 {
                    
                    return false
                }
            }
            
            return true
        }
        
        // sparse matrices are not yet taken care of
        if self.matrixType != .general {
            
            ALog("Unimplemented matrix type!")
            return false
        }
        
        if self.numType == .Double {
            
            var Abuf = self.buffPtr
            var info:__LAPACK_int = 0
            
            withUnsafePointer(to: Int8("U".utf8.first!)) { uplo in
                withUnsafePointer(to: __LAPACK_int(self.rows)) { n in
                    
                    dpotrf_(uplo, n, &Abuf, n, &info)
                }
            }
            
            if info < 0
            {
                PCH_ErrorAlert(message: "DPOTRF Error", info: "Illegal Argument #\(-info)")
                return false
            }
            else if info > 0
            {
                DLog("The matrix is not positive definite (leading minor of order \(info) is not positive definite)")
                return false
            }
            
            if overwriteExistingMatrix {
                
                self.buffPtr = Abuf
                self.factorizationType = .Cholesky
            }
            
            return true
        }
        else {
            
            // must be Complex
            var Abuf = self.buffPtr
            var info:__LAPACK_int = 0
            
            withUnsafePointer(to: Int8("U".utf8.first!)) { uplo in
                withUnsafePointer(to: __LAPACK_int(self.rows)) { n in
                    Abuf.withUnsafeMutableBufferPointer() { aBuf in
                        
                        zpotrf_(uplo, n, OpaquePointer(aBuf.baseAddress!), n, &info)
                    }
                }
            }
            
            if info < 0
            {
                PCH_ErrorAlert(message: "ZPOTRF Error", info: "Illegal Argument #\(-info)")
                return false
            }
            else if info > 0
            {
                DLog("The matrix is not positive definite (leading minor of order \(info) is not positive definite)")
                return false
            }
            
            if overwriteExistingMatrix {
                
                self.buffPtr = Abuf
                self.factorizationType = .Cholesky
            }
            
            return true
        }
    }
    
    /// A  routine to check whether self is a symmetric matrix. Note that this function can be quite slow, so it should not be called in a loop.
    /// - Parameter precision: The precision to which the function tests symmetry. This parameter defaults to the user-settable PchMatrix.equalityPrecision class property
    func TestForSymmetry(precision:Double = PchMatrix.equalityPrecision) -> Bool
    {
        guard self.rows == self.columns else
        {
            DLog("Matrix must be square!")
            return false
        }
        
        if self.numType == .Double
        {
            for i in 0..<self.rows
            {
                for j in i..<self.columns
                {
                    let lhs:Double = self[i, j]!
                    let rhs:Double = self[j, i]!
                   
                    let relativeDiff = fabs((lhs - rhs) / lhs)
                    
                    if relativeDiff > precision {
                        
                        return false
                    }
                }
            }
        }
        else
        {
            for i in 0..<self.rows
            {
                for j in i..<self.columns
                {
                    let lhs:Complex = self[i, j]!
                    let rhs:Complex = self[j, i]!
                    
                    let relativeRealDiff = fabs((lhs.real - rhs.real) / lhs.real)
                    let relativeImagDiff = fabs((lhs.imaginary - rhs.imaginary) / lhs.imaginary)
                    
                    if relativeRealDiff > precision || relativeImagDiff > precision
                    {
                        return false
                    }
                }
            }
        }
        
        return true
    }
}
