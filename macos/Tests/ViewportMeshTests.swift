import Foundation

@main struct ViewportMeshTests {
    static func main() {
        for (columns,rows) in [(7,5),(256,192),(384,136),(152,328),(255,255),(256,255),(512,512),(16,3936)] {
            let candidate = ViewportMesh(columns:columns,rows:rows)
            let reference = ViewportMesh(columns:columns,rows:rows,forceWideIndices:true)
            let old = reference.indices.withUnsafeBytes { Array($0.bindMemory(to:UInt32.self)) }
            let actual: [UInt32] = candidate.indices.withUnsafeBytes {
                candidate.indexBytes == 2 ? $0.bindMemory(to:UInt16.self).map { UInt32($0) } : Array($0.bindMemory(to:UInt32.self))
            }
            precondition(actual == old,"Index topology changed")
            precondition(actual.count == columns*rows*6)
            precondition(actual.max() == UInt32((columns+1)*(rows+1)-1))
            precondition(candidate.indexBytes == (((columns+1)*(rows+1) <= 65536) ? 2 : 4))
            print("\(columns)x\(rows): \(candidate.indexBytes*8)-bit, \(candidate.indices.count) bytes; exact reference indices")
        }
        print("PASS: topology, UInt16 boundary, and UInt32 fallback.")
    }
}
