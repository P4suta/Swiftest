import Foundation
import SwiftestCodec
import Testing

@Test
func strictCodecRejectsDuplicateKeys() {
    do {
        let decoded = try StrictJSON.decode(Data("{\"a\":1,\"a\":2}".utf8))
        Issue.record("unexpected value")
        #expect(StrictJSON.render(decoded).isEmpty)
    } catch let error {
        #expect(error == .duplicateKey(7, "a"))
    }
}

@Test
func objectReaderRejectsUnknownAndMissingFields() throws {
    let value = try StrictJSON.decode(Data("{\"known\":1,\"unknown\":2}".utf8))
    var reader = try JSONObjectReader(value)
    #expect(try reader.requiredInteger("known") == 1)
    do {
        try reader.finish()
        Issue.record("unknown field accepted")
    } catch let error {
        #expect(error == .unknownField("unknown"))
    }
    var missingReader = try JSONObjectReader(.object([:]))
    do {
        let missing = try missingReader.requiredString("required")
        Issue.record("unexpected field")
        #expect(missing.isEmpty)
    } catch let error {
        #expect(error == .missingField("required"))
    }
}

@Test
func unionRequiresExactlyOneKnownTag() throws {
    var reader = try JSONObjectReader(.object(["left": .null, "right": .null]))
    do {
        let union = try reader.exclusiveUnion(allowedTags: ["left", "right"])
        Issue.record("unexpected union")
        #expect(union.tag.isEmpty)
    } catch let error {
        #expect(error == .ambiguousUnion(["left", "right"]))
    }
}

@Test
func canonicalEncodingSortsObjectKeys() {
    let value = JSONValue.object(["z": .number("1"), "a": .boolean(true)])
    #expect(StrictJSON.render(value) == "{\"a\":true,\"z\":1}")
}
