import Foundation
import SwiftestModel

public struct EvidenceTranscript {
    private var bytes = Data()

    public init() {}

    public mutating func append(_ text: String) {
        append(Data(text.utf8))
    }

    public mutating func append(_ data: Data) {
        bytes.append(contentsOf: String(data.count).utf8)
        bytes.append(58)
        bytes.append(data)
    }

    public func digest() throws(DigestError) -> Digest {
        try .sha256(bytes)
    }
}
