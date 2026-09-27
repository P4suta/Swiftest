import Foundation
import SwiftestCodec
import SwiftestModel

public enum XcodeTestInventoryError: Error, Equatable, Sendable {
    case codec(StrictJSONError)
    case identity(XcodeRunIdentityError)
    case reportedErrors
    case ambiguousTestPlans(Int)
    case disabledTests(Int)
    case emptyTests
    case invalidTestPlan(String)
    case invalidIdentifier(String)
    case duplicateIdentifier(String)
    case ambiguousConfigurations(Int)
    case ambiguousDevices(Int)
    case unsupportedNodeType(String)
    case invalidNode(String)
    case unexecutedTest(String)
    case duplicateExecutedIdentifier(String)
    case identityMismatch
    case environmentMismatch
    case failureIdentityMismatch
    case countMismatch
    case resultMismatch
    case invalidDuration(String)
    case countOverflow
}

public struct XcodeTestIdentifier: Hashable, Sendable {
    public let rawValue: String

    private init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    static func decode(_ text: String) throws(XcodeTestInventoryError) -> XcodeTestIdentifier {
        let components = text.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count >= 2,
            !components.contains(where: { $0.isEmpty }),
            text == text.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw .invalidIdentifier(text)
        }
        return XcodeTestIdentifier(text)
    }
}

public struct XcodeTestInventory: Equatable, Sendable {
    public let testPlan: String
    public let identifiers: [XcodeTestIdentifier]

    private init(testPlan: String, identifiers: [XcodeTestIdentifier]) {
        self.testPlan = testPlan
        self.identifiers = identifiers
    }

    public static func decode(_ data: Data) throws(XcodeTestInventoryError) -> XcodeTestInventory {
        let document: JSONValue
        do {
            document = try StrictJSON.decode(data)
        } catch let error {
            throw .codec(error)
        }
        var root = try object(document)
        let errors = try array(&root, "errors")
        let values = try array(&root, "values")
        try finish(root)
        guard errors.isEmpty else {
            throw .reportedErrors
        }
        guard values.count == 1 else {
            throw .ambiguousTestPlans(values.count)
        }
        var plan = try object(values[0])
        let disabled = try array(&plan, "disabledTests")
        let enabled = try array(&plan, "enabledTests")
        let planName = try string(&plan, "testPlan")
        try finish(plan)
        guard disabled.isEmpty else {
            throw .disabledTests(disabled.count)
        }
        guard !enabled.isEmpty else {
            throw .emptyTests
        }
        guard !planName.isEmpty,
            planName == planName.trimmingCharacters(in: .whitespacesAndNewlines),
            !planName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw .invalidTestPlan(planName)
        }
        var identifiers: [XcodeTestIdentifier] = []
        var seen: Set<XcodeTestIdentifier> = []
        for test in enabled {
            var reader = try object(test)
            let identifier = try XcodeTestIdentifier.decode(string(&reader, "identifier"))
            try finish(reader)
            guard seen.insert(identifier).inserted else {
                throw .duplicateIdentifier(identifier.rawValue)
            }
            identifiers.append(identifier)
        }
        return XcodeTestInventory(testPlan: planName, identifiers: identifiers.sorted {
            $0.rawValue < $1.rawValue
        })
    }

    public func verifyExecution(
        _ data: Data,
        summary: XCResultSummary
    ) throws(XcodeTestInventoryError) {
        let document: JSONValue
        do {
            document = try StrictJSON.decode(data)
        } catch let error {
            throw .codec(error)
        }
        var root = try Self.object(document)
        let configurations = try Self.array(&root, "testPlanConfigurations")
        let devices = try Self.array(&root, "devices")
        let roots = try Self.array(&root, "testNodes")
        try Self.finish(root)
        guard configurations.count == 1 else {
            throw .ambiguousConfigurations(configurations.count)
        }
        guard devices.count == 1 else {
            throw .ambiguousDevices(devices.count)
        }
        let configuration: XcodeConfigurationIdentity
        let device: XcodeDeviceIdentity
        do {
            configuration = try .decode(configurations[0])
            device = try .decode(devices[0])
        } catch let error {
            throw .identity(error)
        }
        guard configuration == summary.configuration, device == summary.device else {
            throw .environmentMismatch
        }
        guard roots.count == 1 else {
            throw .ambiguousTestPlans(roots.count)
        }
        let plan = try Self.node(roots[0])
        guard plan.type == "Test Plan", plan.name == testPlan,
            plan.identifier == nil, !plan.children.isEmpty else {
            throw .invalidNode("Test Plan")
        }
        var executed: Set<XcodeTestIdentifier> = []
        var passed = 0
        var failed = 0
        var expectedFailures = 0
        var observedFailures: [XcodeFailureEvidence] = []
        var bundles: Set<String> = []
        var planResult: DescendantResult = .passed
        for bundleValue in plan.children {
            let bundle = try Self.node(bundleValue)
            guard bundle.type == "Unit test bundle" || bundle.type == "UI test bundle",
                !bundle.name.isEmpty, bundle.identifier == nil,
                !bundle.children.isEmpty, bundles.insert(bundle.name).inserted else {
                throw .invalidNode("test bundle")
            }
            var bundleResult: DescendantResult = .passed
            for child in bundle.children {
                let childResult = try Self.collect(
                    child,
                    bundle: bundle.name,
                    executed: &executed,
                    passed: &passed,
                    failed: &failed,
                    expectedFailures: &expectedFailures,
                    observedFailures: &observedFailures
                )
                bundleResult = bundleResult.merging(childResult)
            }
            try Self.validateParentResult(bundle.result, descendants: bundleResult)
            planResult = planResult.merging(bundleResult)
        }
        try Self.validateParentResult(plan.result, descendants: planResult)
        guard executed == Set(identifiers) else {
            throw .identityMismatch
        }
        guard summary.total.rawValue == identifiers.count else {
            throw .countMismatch
        }
        guard summary.passed.rawValue == passed,
            summary.failed.rawValue == failed,
            summary.expectedFailures.rawValue == expectedFailures,
            summary.skipped.rawValue == 0 else {
            throw .resultMismatch
        }
        guard Self.sortedFailures(summary.failures) == Self.sortedFailures(observedFailures) else {
            throw .failureIdentityMismatch
        }
    }

    private enum DescendantResult {
        case passed
        case failed

        func merging(_ other: DescendantResult) -> DescendantResult {
            switch (self, other) {
            case (.passed, .passed):
                return .passed
            case (.passed, .failed), (.failed, .passed), (.failed, .failed):
                return .failed
            }
        }
    }

    private static func validateParentResult(
        _ result: String,
        descendants: DescendantResult
    ) throws(XcodeTestInventoryError) {
        switch (result, descendants) {
        case ("Passed", .passed), ("Failed", .failed):
            return
        default:
            throw .resultMismatch
        }
    }

    private static func increment(_ count: inout Int) throws(XcodeTestInventoryError) {
        let next = count.addingReportingOverflow(1)
        guard !next.overflow else {
            throw .countOverflow
        }
        count = next.partialValue
    }

    private static func sortedFailures(_ failures: [XcodeFailureEvidence]) -> [XcodeFailureEvidence] {
        failures.sorted { left, right in
            if left.identifier.rawValue != right.identifier.rawValue {
                return left.identifier.rawValue < right.identifier.rawValue
            }
            return left.message < right.message
        }
    }

    private static func collect(
        _ input: JSONValue,
        bundle: String,
        executed: inout Set<XcodeTestIdentifier>,
        passed: inout Int,
        failed: inout Int,
        expectedFailures: inout Int,
        observedFailures: inout [XcodeFailureEvidence]
    ) throws(XcodeTestInventoryError) -> DescendantResult {
        let test = try node(input)
        switch test.type {
        case "Test Suite":
            guard test.identifier == nil, !test.name.isEmpty, !test.children.isEmpty else {
                throw .invalidNode("Test Suite")
            }
            var descendants: DescendantResult = .passed
            for child in test.children {
                let childResult = try collect(
                    child,
                    bundle: bundle,
                    executed: &executed,
                    passed: &passed,
                    failed: &failed,
                    expectedFailures: &expectedFailures,
                    observedFailures: &observedFailures
                )
                descendants = descendants.merging(childResult)
            }
            try validateParentResult(test.result, descendants: descendants)
            return descendants
        case "Test Case":
            guard let localIdentifier = test.identifier,
                test.hasIdentifierURL else {
                throw .invalidNode("Test Case")
            }
            let identifier: XcodeTestIdentifier
            do {
                identifier = try .decode(bundle + "/" + localIdentifier)
            } catch let error {
                throw error
            }
            guard executed.insert(identifier).inserted else {
                throw .duplicateExecutedIdentifier(identifier.rawValue)
            }
            switch test.result {
            case "Passed":
                guard test.children.isEmpty else {
                    throw .invalidNode("Test Case")
                }
                try increment(&passed)
                return .passed
            case "Failed":
                guard !test.children.isEmpty else {
                    throw .invalidNode("Test Case")
                }
                for child in test.children {
                    observedFailures.append(try failureMessage(child, identifier: identifier))
                }
                try increment(&failed)
                return .failed
            case "Expected Failure":
                guard test.children.isEmpty else {
                    throw .invalidNode("Test Case")
                }
                try increment(&expectedFailures)
                return .passed
            case "Skipped":
                throw .unexecutedTest(identifier.rawValue)
            default:
                throw .invalidNode("Test Case result")
            }
        default:
            throw .unsupportedNodeType(test.type)
        }
    }

    private static func failureMessage(
        _ input: JSONValue,
        identifier: XcodeTestIdentifier
    ) throws(XcodeTestInventoryError) -> XcodeFailureEvidence {
        var reader = try object(input)
        let type = try string(&reader, "nodeType")
        let message = try string(&reader, "name")
        let locationValue = try readerValue(&reader, "sourceLocation")
        try finish(reader)
        guard type == "Failure Message", !message.isEmpty else {
            throw .invalidNode("Failure Message")
        }
        var location = try object(locationValue)
        let path = try string(&location, "filePath")
        let lineValue = try readerValue(&location, "lineNumber")
        try finish(location)
        guard !path.isEmpty,
            case .number(let digits) = lineValue,
            let line = Int(digits), line > 0 else {
            throw .invalidNode("sourceLocation")
        }
        return XcodeFailureEvidence(identifier: identifier, message: message)
    }

    private struct TestNode {
        let type: String
        let name: String
        let identifier: String?
        let hasIdentifierURL: Bool
        let result: String
        let children: [JSONValue]
    }

    private static func node(_ input: JSONValue) throws(XcodeTestInventoryError) -> TestNode {
        guard case .object(let fields) = input else {
            throw .codec(.expectedObject)
        }
        var reader = try object(input)
        let type = try string(&reader, "nodeType")
        let name = try string(&reader, "name")
        let result = try string(&reader, "result")
        let identifier: String?
        if fields["nodeIdentifier"] != nil {
            identifier = try string(&reader, "nodeIdentifier")
        } else {
            identifier = nil
        }
        let hasIdentifierURL = fields["nodeIdentifierURL"] != nil
        if hasIdentifierURL {
            let url = try string(&reader, "nodeIdentifierURL")
            guard !url.isEmpty else {
                throw .invalidNode("nodeIdentifierURL")
            }
        }
        let children: [JSONValue]
        if fields["children"] != nil {
            children = try array(&reader, "children")
        } else {
            children = []
        }
        if fields["duration"] != nil {
            let duration = try string(&reader, "duration")
            guard !duration.isEmpty else {
                throw .invalidDuration("duration")
            }
        }
        if fields["durationInSeconds"] != nil {
            let value = try readerValue(&reader, "durationInSeconds")
            guard case .number(let text) = value,
                let seconds = Double(text), seconds.isFinite, seconds >= 0 else {
                throw .invalidDuration("durationInSeconds")
            }
        }
        try finish(reader)
        guard !name.isEmpty,
            ["Passed", "Failed", "Expected Failure", "Skipped"].contains(result) else {
            throw .invalidNode(type)
        }
        return TestNode(
            type: type,
            name: name,
            identifier: identifier,
            hasIdentifierURL: hasIdentifierURL,
            result: result,
            children: children
        )
    }

    private static func object(_ value: JSONValue) throws(XcodeTestInventoryError) -> JSONObjectReader {
        do {
            return try JSONObjectReader(value)
        } catch let error {
            throw .codec(error)
        }
    }

    private static func array(
        _ reader: inout JSONObjectReader,
        _ key: String
    ) throws(XcodeTestInventoryError) -> [JSONValue] {
        do {
            return try reader.requiredArray(key)
        } catch let error {
            throw .codec(error)
        }
    }

    private static func string(
        _ reader: inout JSONObjectReader,
        _ key: String
    ) throws(XcodeTestInventoryError) -> String {
        do {
            return try reader.requiredString(key)
        } catch let error {
            throw .codec(error)
        }
    }

    private static func readerValue(
        _ reader: inout JSONObjectReader,
        _ key: String
    ) throws(XcodeTestInventoryError) -> JSONValue {
        do {
            return try reader.requiredValue(key)
        } catch let error {
            throw .codec(error)
        }
    }

    private static func finish(_ reader: JSONObjectReader) throws(XcodeTestInventoryError) {
        do {
            try reader.finish()
        } catch let error {
            throw .codec(error)
        }
    }
}
