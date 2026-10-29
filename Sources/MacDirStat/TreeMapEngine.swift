import Foundation
import CoreGraphics

public struct TreeMapEngine {
    public static let minDimension: CGFloat = 1.0

    /// Computes squarified treemap layout using Bruls, Huizing, van Wijk algorithm
    public static func layout(item: FileItem, in rect: CGRect) {
        item.bounds = rect
        if rect.width < minDimension || rect.height < minDimension || item.children.isEmpty {
            return
        }
        
        let validChildren = item.children
            .filter { $0.size > 0 }
            .sorted(by: { $0.size > $1.size })
        
        guard !validChildren.isEmpty else { return }
        let totalWeight = validChildren.reduce(UInt64(0)) { $0 + $1.size }
        guard totalWeight > 0 else { return }
        
        squarify(children: validChildren, parentWeight: totalWeight, bounds: rect)
        
        // Recursively lay out children within their designated bounds
        for child in validChildren {
            if child.isDirectory && !child.isPackage && child.bounds.width >= 4 && child.bounds.height >= 4 {
                // Inset by 1px cushion border matching WinDirStat
                let inner = child.bounds.insetBy(dx: 1, dy: 1)
                layout(item: child, in: inner)
            }
        }
    }
    
    private static func squarify(children: [FileItem], parentWeight: UInt64, bounds: CGRect) {
        var remaining = bounds
        var remainingWeight = Double(parentWeight)
        var head = 0
        let weights = children.map { Double($0.size) }
        
        while head < children.count && remaining.width > 0.5 && remaining.height > 0.5 {
            let horizontal = remaining.width >= remaining.height
            let rowThickness = horizontal ? remaining.height : remaining.width
            let weightPerPixel = remainingWeight / Double(max(1.0, remaining.width * remaining.height))
            let squaredRowWeight = rowThickness * rowThickness * weightPerPixel
            
            let rowBegin = head
            var rowEnd = head
            var worst = Double.greatestFiniteMagnitude
            let largest = weights[rowBegin]
            var rowWeight = 0.0
            
            while rowEnd < children.count {
                let childWeight = weights[rowEnd]
                if childWeight <= 0 {
                    rowEnd = children.count
                    break
                }
                
                let nextWeight = rowWeight + childWeight
                let squaredWeight = nextWeight * nextWeight
                let nextWorst = max(
                    (squaredRowWeight * largest) / squaredWeight,
                    squaredWeight / (squaredRowWeight * childWeight)
                )
                
                if nextWorst > worst && rowEnd > rowBegin { break }
                rowWeight += childWeight
                rowEnd += 1
                worst = nextWorst
            }
            
            if rowWeight <= 0 { break }
            
            let remainingExtent = horizontal ? remaining.width : remaining.height
            let rowWidth: CGFloat
            if rowEnd == children.count {
                rowWidth = remainingExtent
            } else {
                let computed = CGFloat(rowWeight / remainingWeight) * remainingExtent
                rowWidth = max(1.0, min(remainingExtent, computed))
            }
            
            var rowBounds = remaining
            if horizontal {
                rowBounds.size.width = rowWidth
            } else {
                rowBounds.size.height = rowWidth
            }
            
            var begin = horizontal ? rowBounds.minY : rowBounds.minX
            let rowExtent = horizontal ? rowBounds.height : rowBounds.width
            
            for i in rowBegin..<rowEnd {
                let child = children[i]
                let isLastInRow = (i + 1 == rowEnd)
                let length: CGFloat
                if isLastInRow {
                    let maxCoord = horizontal ? rowBounds.maxY : rowBounds.maxX
                    length = max(0, maxCoord - begin)
                } else {
                    let fraction = CGFloat(weights[i] / rowWeight)
                    length = max(0, fraction * rowExtent)
                }
                let end = begin + length
                
                if horizontal {
                    child.bounds = CGRect(x: rowBounds.minX, y: begin, width: rowBounds.width, height: max(0, end - begin))
                } else {
                    child.bounds = CGRect(x: begin, y: rowBounds.minY, width: max(0, end - begin), height: rowBounds.height)
                }
                begin = end
            }
            
            if horizontal {
                remaining.origin.x += rowWidth
                remaining.size.width = max(0, remaining.size.width - rowWidth)
            } else {
                remaining.origin.y += rowWidth
                remaining.size.height = max(0, remaining.size.height - rowWidth)
            }
            
            remainingWeight = max(0, remainingWeight - rowWeight)
            head = rowEnd
        }
    }
}
