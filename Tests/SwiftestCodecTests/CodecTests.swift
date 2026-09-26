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

@Test
func strictCodecBoundsRecursiveDepth() throws {
    let accepted = String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64)
    let decoded = try StrictJSON.decode(Data(accepted.utf8))
    #expect(StrictJSON.render(decoded) == accepted)
    let rejected = "[" + accepted + "]"
    do {
        let value = try StrictJSON.decode(Data(rejected.utf8))
        Issue.record("excessively nested JSON accepted")
        #expect(value == .null)
    } catch let error {
        #expect(error == .resourceLimit(.depth))
    }
}

@Test
func strictCodecBoundsTotalNodes() {
    let rejected = "[" + String(repeating: "0,", count: 199_999) + "0]"
    do {
        let value = try StrictJSON.decode(Data(rejected.utf8))
        Issue.record("excessive JSON nodes accepted")
        #expect(value == .null)
    } catch let error {
        #expect(error == .resourceLimit(.nodes))
    }
}

@Test
func strictCodecBoundsInputBytesBeforeParsing() {
    let rejected = Data(repeating: 32, count: 32_000_001)
    do {
        let value = try StrictJSON.decode(rejected)
        Issue.record("oversized JSON accepted")
        #expect(value == .null)
    } catch let error {
        #expect(error == .resourceLimit(.bytes))
    }
}

@Test
func xunitCountsActualCasesAndFailureKinds() throws {
    let source = """
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuites tests="3" failures="1" errors="0" skipped="1">
          <testsuite name="Module" tests="3" failures="1" errors="0" skipped="1">
            <testcase classname="Suite" name="passes"/>
            <testcase classname="Suite" name="fails"><failure message="a &amp; b"/></testcase>
            <testcase classname="Suite" name="skips"><skipped/></testcase>
          </testsuite>
        </testsuites>
        """
    let report = try XUnitCodec.decode(Data(source.utf8))
    #expect(report.tests.rawValue == 3)
    #expect(report.failures.rawValue == 1)
    #expect(report.errors.rawValue == 0)
    #expect(report.skipped.rawValue == 1)
    #expect(report.cases.map(\.status) == [.passed, .failed, .skipped])
}

@Test
func xunitCombinesSwiftTestingAndXCTestDocuments() throws {
    let swiftTesting = """
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuites>
          <testsuite name="TestResults" errors="0" tests="1" failures="0" skipped="0" time="0.001">
            <testcase classname="SmokeTests" name="swiftTestingPasses()" time="0.001" />
          </testsuite>
        </testsuites>
        """
    let xctest = """
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuites>
          <testsuite name="TestResults" errors="0" tests="1" failures="0" time="0.001">
            <testcase classname="SmokeTests.XCTestSmoke" name="testXCTestPasses" time="0.001"></testcase>
          </testsuite>
        </testsuites>
        """
    let report = try XUnitCodec.decodeDocuments([Data(swiftTesting.utf8), Data(xctest.utf8)])
    #expect(report.tests.rawValue == 2)
    #expect(report.cases.count == 2)
    #expect(report.failures.rawValue == 0)
}

@Test
func xunitRejectsDuplicateAttributesUnknownRootAndCountFraud() {
    let malformed: [(String, XUnitCodecError)] = [
        ("<testsuite name=\"S\" tests=\"1\" tests=\"1\" failures=\"0\" errors=\"0\" skipped=\"0\"><testcase name=\"T\"/></testsuite>", .duplicateAttribute("tests")),
        ("<report tests=\"0\"/>", .unknownElement("report")),
        ("<testsuite name=\"S\" tests=\"-1\" failures=\"0\" errors=\"0\" skipped=\"0\"/>", .invalidCount("tests", "-1")),
        ("<testsuite name=\"S\" tests=\"1\" failures=\"0\" errors=\"0\" skipped=\"0\"/>", .countMismatch("testsuite")),
        ("<testsuite name=\"S\" tests=\"0\" failures=\"0\" errors=\"0\" skipped=\"0\" alien=\"1\"/>", .unknownAttribute("testsuite", "alien")),
    ]
    for (xml, expected) in malformed {
        do {
            let report = try XUnitCodec.decode(Data(xml.utf8))
            Issue.record("malformed xUnit accepted")
            #expect(report.tests.rawValue < 0)
        } catch let error {
            #expect(error == expected)
        }
    }
}

@Test
func xunitRejectsMalformedNestingDuplicateCasesAndExternalEntities() {
    let malformed: [String] = [
        "<testsuite name=\"S\" tests=\"1\" failures=\"0\" errors=\"0\" skipped=\"0\"><testcase name=\"T\"></testsuite>",
        "<testsuite name=\"S\" tests=\"2\" failures=\"0\" errors=\"0\" skipped=\"0\"><testcase name=\"T\"/><testcase name=\"T\"/></testsuite>",
        "<!DOCTYPE testsuite [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><testsuite name=\"S\" tests=\"0\" failures=\"0\" errors=\"0\" skipped=\"0\"/>",
        "<testsuite name=\"S &malicious;\" tests=\"0\" failures=\"0\" errors=\"0\" skipped=\"0\"/>",
    ]
    for (index, xml) in malformed.enumerated() {
        do {
            let report = try XUnitCodec.decode(Data(xml.utf8))
            Issue.record("malformed xUnit accepted")
            #expect(report.tests.rawValue < 0)
        } catch let error {
            switch index {
            case 0, 2:
                if case .malformedXML = error {
                    break
                }
                Issue.record("malformed XML produced a different error")
            case 1:
                #expect(error == .duplicateTestCase("S.T"))
            case 3:
                #expect(error == .invalidEntity("malicious"))
            default:
                Issue.record("unexpected specimen")
            }
        }
    }
}
