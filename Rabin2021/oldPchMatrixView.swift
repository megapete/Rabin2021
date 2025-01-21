//
//  PchMatrixView.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2024-12-16.
//

import Cocoa
import PchBasePackage
import PchMatrixPackage

class PchMatrixView: NSViewController {
    
    @IBOutlet weak var tableView: NSTableView!
    
    var matrix:PchMatrix? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        // collectionView.register(MaxVoltageDiffsViewItem.self, forItemWithIdentifier: MaxVoltageDiffsViewItem.reuseIdentifier)
        // tableView.register(NSNib(nibNamed: "PchMatrixViewItem", bundle: nil), forIdentifier: PchMatrixViewItem.reuseIdentifier)
        
        guard let theMatrix = self.matrix else {
            
            ALog("Matrix not defined!")
            return
        }
        
        // let cellColumn = NSTableColumn(identifier: PchMatrixViewItem.reuseIdentifier)
        for i in 0..<theMatrix.columns {
            
            let colIdentfier = NSUserInterfaceItemIdentifier("\(i)")
            let cellColumn = NSTableColumn(identifier: colIdentfier)
            cellColumn.minWidth = PchMatrixViewItem.cellWidth
            cellColumn.maxWidth = cellColumn.minWidth
            tableView.addTableColumn(cellColumn)
            tableView.register(NSNib(nibNamed: "PchMatrixViewItem", bundle: nil), forIdentifier:cellColumn.identifier)
        }
        
        // tableView.removeTableColumn(tableView.tableColumns[0])
        tableView.reloadData()
        
        for nextColumn in tableView.tableColumns {
            
            let colWidth = nextColumn.width
            print("ColWidth: \(colWidth)")
        }
    }
    
    
    
}

extension PchMatrixView:NSTableViewDelegate {
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        
        guard let theMatrix = self.matrix else {
            
            DLog("No matrix defined!")
            return nil
        }
        
        
        // take care of the case where it's the header row (holds row numbers)
        if tableColumn == tableView.tableColumns[0] {
            
            let cellView = tableView.makeView(withIdentifier: tableColumn!.identifier, owner: self) as! NSTableCellView
            cellView.textField?.integerValue = row
            // print(cellView.textField!.stringValue)
            return cellView
        }
        
        guard let columnID = tableColumn?.identifier else {
            
            DLog("No column??")
            return nil
        }
        
        guard let colIndex = Int(columnID.rawValue) else {
            
            DLog("Could not extract index from column identifier")
            return nil
        }
        
        guard let cellValue:Double = theMatrix[row, colIndex] else {
            
            DLog("Could not get value from matrix!")
            return nil
        }
        
        let cellView = tableView.makeView(withIdentifier: columnID, owner: self) as! PchMatrixViewItem
        cellView.textField?.doubleValue = cellValue
        
        // print(cellView.textField!.stringValue)
        return cellView
    }
}

extension PchMatrixView:NSTableViewDataSource {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        
        if let theMatrix = self.matrix {
            
            return theMatrix.rows
        }
        
        return 0
    }
    
    
}
