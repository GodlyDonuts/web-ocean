import Foundation

// Preserve the exact topology while minimizing index bandwidth. Extremely tall
// or wide layouts can cross the UInt16 vertex limit and retain UInt32 indices.
struct ViewportMesh {
    let indices: Data
    let indexBytes: Int

    init(columns: Int, rows: Int, forceWideIndices: Bool = false) {
        precondition(columns > 0 && rows > 0)
        let narrow = !forceWideIndices && (columns+1)*(rows+1) <= 65536
        indexBytes = narrow ? 2 : 4
        indices = narrow ? Self.makeIndices(UInt16.self,columns:columns,rows:rows)
                         : Self.makeIndices(UInt32.self,columns:columns,rows:rows)
    }

    private static func makeIndices<T: FixedWidthInteger>(_ type: T.Type, columns: Int, rows: Int) -> Data {
        var indices: [T] = []
        indices.reserveCapacity(columns*rows*6)
        for y in 0..<rows { for x in 0..<columns {
            let a = y*(columns+1)+x, b = a+1, c = a+columns+1, d = c+1
            indices.append(contentsOf:[T(a),T(c),T(d),T(a),T(d),T(b)])
        } }
        return indices.withUnsafeBytes { Data($0) }
    }
}
