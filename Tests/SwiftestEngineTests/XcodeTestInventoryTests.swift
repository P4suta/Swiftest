import Foundation
@testable import SwiftestEngine
import SwiftestModel
import Testing

private let xcode27Enumeration = """
{
  "errors" : [],
  "values" : [
    {
      "disabledTests" : [],
      "enabledTests" : [
        { "identifier" : "SmokeTests/SmokeTests/testAlpha()" },
        { "identifier" : "SmokeTests/SmokeTests/testBeta()" },
        { "identifier" : "SmokeTests/swiftExample()" },
        { "identifier" : "SmokeTests/swiftParameterized(_:)" }
      ],
      "testPlan" : "Smoke"
    }
  ]
}
"""

private let xcode27SimpleEnumeration = """
{"errors":[],"values":[{"disabledTests":[],"enabledTests":[{"identifier":"SmokeTests/SmokeTests/testAlpha()"},{"identifier":"SmokeTests/SmokeTests/testBeta()"},{"identifier":"SmokeTests/swiftExample()"}],"testPlan":"Smoke"}]}
"""

private let xcode27Execution = """
{"devices":[{"architecture":"arm64e","deviceId":"00006050-001A19043E07401C","deviceName":"My Mac","modelName":"MacBook Pro","osBuildNumber":"26A428","osVersion":"27.0","platform":"macOS"}],"testNodes":[{"children":[{"children":[{"children":[{"duration":"0.000024s","durationInSeconds":0.000024,"name":"swiftExample()","nodeIdentifier":"swiftExample()","nodeIdentifierURL":"test://com.apple.xcode/Smoke/SmokeTests/swiftExample()","nodeType":"Test Case","result":"Passed"},{"duration":"0.00068s","durationInSeconds":0.00068,"name":"testAlpha()","nodeIdentifier":"SmokeTests/testAlpha()","nodeIdentifierURL":"test://com.apple.xcode/Smoke/SmokeTests/SmokeTests/testAlpha","nodeType":"Test Case","result":"Passed"},{"duration":"0.00035s","durationInSeconds":0.00035,"name":"testBeta()","nodeIdentifier":"SmokeTests/testBeta()","nodeIdentifierURL":"test://com.apple.xcode/Smoke/SmokeTests/SmokeTests/testBeta","nodeType":"Test Case","result":"Passed"}],"name":"SmokeTests","nodeIdentifierURL":"test://com.apple.xcode/Smoke/SmokeTests/SmokeTests","nodeType":"Test Suite","result":"Passed"}],"name":"SmokeTests","nodeIdentifierURL":"test://com.apple.xcode/Smoke/SmokeTests","nodeType":"Unit test bundle","result":"Passed"}],"name":"Smoke","nodeType":"Test Plan","result":"Passed"}],"testPlanConfigurations":[{"configurationId":"1","configurationName":"Test Scheme Action"}]}
"""

private func passingSummary(_ count: Int) throws -> XCResultSummary {
    let document = """
    {"title":"Tests","environmentDescription":"macOS","topInsights":[],"result":"Passed","totalTestCount":\(count),"passedTests":\(count),"failedTests":0,"skippedTests":0,"expectedFailures":0,"statistics":[],"devicesAndConfigurations":[{"device":{"architecture":"arm64e","deviceId":"00006050-001A19043E07401C","deviceName":"My Mac","modelName":"MacBook Pro","osBuildNumber":"26A428","osVersion":"27.0","platform":"macOS"},"testPlanConfiguration":{"configurationId":"1","configurationName":"Test Scheme Action"},"passedTests":\(count),"failedTests":0,"skippedTests":0,"expectedFailures":0}],"testFailures":[],"runtimeWarnings":[]}
    """
    return try XCResultSummary.decode(Data(document.utf8))
}

private func failedSummary(_ identifier: String) throws -> XCResultSummary {
    let document = """
    {"title":"Tests","environmentDescription":"macOS","topInsights":[],"result":"Failed","totalTestCount":3,"passedTests":2,"failedTests":1,"skippedTests":0,"expectedFailures":0,"statistics":[],"devicesAndConfigurations":[{"device":{"architecture":"arm64e","deviceId":"00006050-001A19043E07401C","deviceName":"My Mac","modelName":"MacBook Pro","osBuildNumber":"26A428","osVersion":"27.0","platform":"macOS"},"testPlanConfiguration":{"configurationId":"1","configurationName":"Test Scheme Action"},"passedTests":2,"failedTests":1,"skippedTests":0,"expectedFailures":0}],"testFailures":[{"testName":"testBeta()","targetName":"SmokeTests","failureText":"assertion failed","testIdentifierString":"\(identifier)","testIdentifier":1}],"runtimeWarnings":[]}
    """
    return try XCResultSummary.decode(Data(document.utf8))
}

private let xcode27FailedExecution = xcode27Execution.replacingOccurrences(
    of: "\"nodeIdentifier\":\"SmokeTests/testBeta()\",\"nodeIdentifierURL\":\"test://com.apple.xcode/Smoke/SmokeTests/SmokeTests/testBeta\",\"nodeType\":\"Test Case\",\"result\":\"Passed\"",
    with: "\"children\":[{\"name\":\"assertion failed\",\"nodeType\":\"Failure Message\",\"sourceLocation\":{\"filePath\":\"/tmp/SmokeTests.swift\",\"lineNumber\":10}}],\"nodeIdentifier\":\"SmokeTests/testBeta()\",\"nodeIdentifierURL\":\"test://com.apple.xcode/Smoke/SmokeTests/SmokeTests/testBeta\",\"nodeType\":\"Test Case\",\"result\":\"Failed\""
).replacingOccurrences(
    of: "\"nodeType\":\"Test Suite\",\"result\":\"Passed\"",
    with: "\"nodeType\":\"Test Suite\",\"result\":\"Failed\""
).replacingOccurrences(
    of: "\"nodeType\":\"Unit test bundle\",\"result\":\"Passed\"",
    with: "\"nodeType\":\"Unit test bundle\",\"result\":\"Failed\""
).replacingOccurrences(
    of: "\"nodeType\":\"Test Plan\",\"result\":\"Passed\"",
    with: "\"nodeType\":\"Test Plan\",\"result\":\"Failed\""
)

@Test
func xcode27EnumerationDecodesExactIdentifiers() throws {
    let inventory = try XcodeTestInventory.decode(Data(xcode27Enumeration.utf8))
    #expect(inventory.testPlan == "Smoke")
    #expect(inventory.identifiers.map(\.rawValue) == [
        "SmokeTests/SmokeTests/testAlpha()",
        "SmokeTests/SmokeTests/testBeta()",
        "SmokeTests/swiftExample()",
        "SmokeTests/swiftParameterized(_:)",
    ])
}

@Test
func xcodeEnumerationRejectsUnknownAndDuplicateFields() {
    let unknown = xcode27Enumeration.replacingOccurrences(
        of: "\"testPlan\" : \"Smoke\"",
        with: "\"testPlan\" : \"Smoke\", \"surprise\" : true"
    )
    #expect(throws: XcodeTestInventoryError.codec(.unknownField("surprise"))) {
        try XcodeTestInventory.decode(Data(unknown.utf8))
    }
    let duplicate = xcode27Enumeration.replacingOccurrences(
        of: "\"errors\" : [],",
        with: "\"errors\" : [], \"errors\" : [],"
    )
    #expect(throws: XcodeTestInventoryError.self) {
        try XcodeTestInventory.decode(Data(duplicate.utf8))
    }
    let testField = xcode27Enumeration.replacingOccurrences(
        of: "\"identifier\" : \"SmokeTests/SmokeTests/testAlpha()\"",
        with: "\"identifier\" : \"SmokeTests/SmokeTests/testAlpha()\", \"details\" : \"hidden\""
    )
    #expect(throws: XcodeTestInventoryError.codec(.unknownField("details"))) {
        try XcodeTestInventory.decode(Data(testField.utf8))
    }
}

@Test
func xcodeEnumerationRejectsErrorsDisabledAndAmbiguousPlans() {
    let errors = xcode27Enumeration.replacingOccurrences(
        of: "\"errors\" : []",
        with: "\"errors\" : [\"launch failed\"]"
    )
    #expect(throws: XcodeTestInventoryError.reportedErrors) {
        try XcodeTestInventory.decode(Data(errors.utf8))
    }
    let disabled = xcode27Enumeration.replacingOccurrences(
        of: "\"disabledTests\" : []",
        with: "\"disabledTests\" : [{\"identifier\":\"SmokeTests/skipped()\"}]"
    )
    #expect(throws: XcodeTestInventoryError.disabledTests(1)) {
        try XcodeTestInventory.decode(Data(disabled.utf8))
    }
    let secondPlan = """
    {"errors":[],"values":[{"disabledTests":[],"enabledTests":[{"identifier":"A/a()"}],"testPlan":"A"},{"disabledTests":[],"enabledTests":[{"identifier":"B/b()"}],"testPlan":"B"}]}
    """
    #expect(throws: XcodeTestInventoryError.ambiguousTestPlans(2)) {
        try XcodeTestInventory.decode(Data(secondPlan.utf8))
    }
}

@Test
func xcodeEnumerationRejectsDuplicateAndMalformedIdentifiers() {
    let repeated = xcode27Enumeration.replacingOccurrences(
        of: "SmokeTests/SmokeTests/testBeta()",
        with: "SmokeTests/SmokeTests/testAlpha()"
    )
    #expect(throws: XcodeTestInventoryError.duplicateIdentifier("SmokeTests/SmokeTests/testAlpha()")) {
        try XcodeTestInventory.decode(Data(repeated.utf8))
    }
    for invalid in ["", "SmokeTests", "/test()", "SmokeTests//test()", "SmokeTests/test()\n"] {
        let document = """
        {"errors":[],"values":[{"disabledTests":[],"enabledTests":[{"identifier":"\(invalid)"}],"testPlan":"Smoke"}]}
        """
        #expect(throws: XcodeTestInventoryError.self) {
            try XcodeTestInventory.decode(Data(document.utf8))
        }
    }
}

@Test
func xcodeExecutionMatchesExactEnumeratedIdentifiers() throws {
    let inventory = try XcodeTestInventory.decode(Data(xcode27SimpleEnumeration.utf8))
    try inventory.verifyExecution(Data(xcode27Execution.utf8), summary: passingSummary(3))
    let invocation = XcodeAppTestDriver.enumerateInvocation(
        xctestrun: "/tmp/Build/Products/Smoke.xctestrun",
        destination: "platform=macOS",
        derivedData: "/tmp/DerivedData",
        workingDirectory: "/tmp"
    )
    #expect(invocation.arguments == [
        "xcodebuild", "-quiet",
        "-xctestrun", "/tmp/Build/Products/Smoke.xctestrun",
        "-destination", "platform=macOS",
        "-derivedDataPath", "/tmp/DerivedData",
        "-test-enumeration-style", "flat",
        "-test-enumeration-format", "json",
        "-test-enumeration-output-path", "-",
        "test-without-building", "-enumerate-tests",
    ])
    let executedInvocation = XcodeAppTestDriver.executedTestsInvocation(
        resultBundle: "/tmp/Test.xcresult",
        workingDirectory: "/tmp"
    )
    #expect(executedInvocation.arguments == [
        "xcresulttool", "get", "test-results", "tests",
        "--path", "/tmp/Test.xcresult",
        "--schema-version", "0.4.0", "--compact",
    ])
}

@Test
func xcodeExecutionRejectsIdentitySubstitutionAndDuplicates() throws {
    let inventory = try XcodeTestInventory.decode(Data(xcode27SimpleEnumeration.utf8))
    let substituted = xcode27Execution.replacingOccurrences(
        of: "\"nodeIdentifier\":\"SmokeTests/testBeta()\"",
        with: "\"nodeIdentifier\":\"SmokeTests/testGamma()\""
    )
    #expect(throws: XcodeTestInventoryError.identityMismatch) {
        try inventory.verifyExecution(Data(substituted.utf8), summary: passingSummary(3))
    }
    let duplicate = xcode27Execution.replacingOccurrences(
        of: "\"nodeIdentifier\":\"SmokeTests/testBeta()\"",
        with: "\"nodeIdentifier\":\"SmokeTests/testAlpha()\""
    )
    #expect(throws: XcodeTestInventoryError.duplicateExecutedIdentifier("SmokeTests/SmokeTests/testAlpha()")) {
        try inventory.verifyExecution(Data(duplicate.utf8), summary: passingSummary(3))
    }
}

@Test
func xcodeExecutionRejectsParameterizedCardinalityDespiteEqualSummaryCount() throws {
    let inventory = try XcodeTestInventory.decode(Data(xcode27Enumeration.utf8))
    let parameterized = xcode27Execution.replacingOccurrences(
        of: "{\"duration\":\"0.00068s\"",
        with: "{\"children\":[{\"name\":\"1\",\"nodeType\":\"Arguments\",\"result\":\"Passed\"},{\"name\":\"2\",\"nodeType\":\"Arguments\",\"result\":\"Passed\"}],\"duration\":\"0.00068s\""
    ).replacingOccurrences(
        of: "\"nodeIdentifier\":\"SmokeTests/testAlpha()\"",
        with: "\"nodeIdentifier\":\"swiftParameterized(_:)\""
    )
    #expect(throws: XcodeTestInventoryError.invalidNode("Test Case")) {
        try inventory.verifyExecution(Data(parameterized.utf8), summary: passingSummary(4))
    }
}

@Test
func xcodeExecutionRejectsUnknownNodesAndMultipleConfigurations() throws {
    let inventory = try XcodeTestInventory.decode(Data(xcode27SimpleEnumeration.utf8))
    let unknown = xcode27Execution.replacingOccurrences(
        of: "\"name\":\"swiftExample()\"",
        with: "\"name\":\"swiftExample()\",\"undocumented\":true"
    )
    #expect(throws: XcodeTestInventoryError.codec(.unknownField("undocumented"))) {
        try inventory.verifyExecution(Data(unknown.utf8), summary: passingSummary(3))
    }
    let configurations = xcode27Execution.replacingOccurrences(
        of: "\"configurationName\":\"Test Scheme Action\"}",
        with: "\"configurationName\":\"Test Scheme Action\"},{\"configurationId\":\"2\",\"configurationName\":\"Other\"}"
    )
    #expect(throws: XcodeTestInventoryError.ambiguousConfigurations(2)) {
        try inventory.verifyExecution(Data(configurations.utf8), summary: passingSummary(3))
    }
    let repetition = xcode27Execution.replacingOccurrences(
        of: "\"nodeType\":\"Test Suite\"",
        with: "\"nodeType\":\"Repetition\""
    )
    #expect(throws: XcodeTestInventoryError.unsupportedNodeType("Repetition")) {
        try inventory.verifyExecution(Data(repetition.utf8), summary: passingSummary(3))
    }
}

@Test
func xcodeExecutionRejectsSkippedAndContradictoryCounts() throws {
    let inventory = try XcodeTestInventory.decode(Data(xcode27SimpleEnumeration.utf8))
    let skipped = xcode27Execution.replacingOccurrences(
        of: "\"nodeIdentifier\":\"SmokeTests/testBeta()\",\"nodeIdentifierURL\":\"test://com.apple.xcode/Smoke/SmokeTests/SmokeTests/testBeta\",\"nodeType\":\"Test Case\",\"result\":\"Passed\"",
        with: "\"nodeIdentifier\":\"SmokeTests/testBeta()\",\"nodeIdentifierURL\":\"test://com.apple.xcode/Smoke/SmokeTests/SmokeTests/testBeta\",\"nodeType\":\"Test Case\",\"result\":\"Skipped\""
    )
    #expect(throws: XcodeTestInventoryError.unexecutedTest("SmokeTests/SmokeTests/testBeta()")) {
        try inventory.verifyExecution(Data(skipped.utf8), summary: passingSummary(3))
    }
    #expect(throws: XcodeTestInventoryError.countMismatch) {
        try inventory.verifyExecution(Data(xcode27Execution.utf8), summary: passingSummary(4))
    }
}

@Test
func xcodeExecutionRejectsContradictoryParentResults() throws {
    let inventory = try XcodeTestInventory.decode(Data(xcode27SimpleEnumeration.utf8))
    let failedParent = xcode27Execution.replacingOccurrences(
        of: "\"name\":\"Smoke\",\"nodeType\":\"Test Plan\",\"result\":\"Passed\"",
        with: "\"name\":\"Smoke\",\"nodeType\":\"Test Plan\",\"result\":\"Failed\""
    )
    #expect(throws: XcodeTestInventoryError.resultMismatch) {
        try inventory.verifyExecution(Data(failedParent.utf8), summary: passingSummary(3))
    }
    let failedCase = xcode27FailedExecution.replacingOccurrences(
        of: "\"nodeType\":\"Test Plan\",\"result\":\"Failed\"",
        with: "\"nodeType\":\"Test Plan\",\"result\":\"Passed\""
    )
    #expect(throws: XcodeTestInventoryError.resultMismatch) {
        try inventory.verifyExecution(Data(failedCase.utf8), summary: passingSummary(3))
    }
}

@Test
func xcodeExecutionRejectsDeviceAndConfigurationSubstitution() throws {
    let inventory = try XcodeTestInventory.decode(Data(xcode27SimpleEnumeration.utf8))
    let summary = try passingSummary(3)
    let otherDevice = xcode27Execution.replacingOccurrences(
        of: "\"deviceId\":\"00006050-001A19043E07401C\"",
        with: "\"deviceId\":\"another-device\""
    )
    #expect(throws: XcodeTestInventoryError.environmentMismatch) {
        try inventory.verifyExecution(Data(otherDevice.utf8), summary: summary)
    }
    let otherConfiguration = xcode27Execution.replacingOccurrences(
        of: "\"configurationId\":\"1\"",
        with: "\"configurationId\":\"2\""
    )
    #expect(throws: XcodeTestInventoryError.environmentMismatch) {
        try inventory.verifyExecution(Data(otherConfiguration.utf8), summary: summary)
    }
}

@Test
func xcodeExecutionRejectsFailureIdentifierSubstitution() throws {
    let inventory = try XcodeTestInventory.decode(Data(xcode27SimpleEnumeration.utf8))
    let failed = Data(xcode27FailedExecution.utf8)
    try inventory.verifyExecution(
        failed,
        summary: failedSummary("SmokeTests/testBeta()")
    )
    #expect(throws: XcodeTestInventoryError.failureIdentityMismatch) {
        try inventory.verifyExecution(
            failed,
            summary: failedSummary("SmokeTests/testAlpha()")
        )
    }
}

@Test
func xcodeFailureMessagesRequireClosedShapeAndExactText() throws {
    let inventory = try XcodeTestInventory.decode(Data(xcode27SimpleEnumeration.utf8))
    let summary = try failedSummary("SmokeTests/testBeta()")
    let unknown = xcode27FailedExecution.replacingOccurrences(
        of: "\"nodeType\":\"Failure Message\"",
        with: "\"nodeType\":\"Failure Message\",\"undocumented\":true"
    )
    #expect(throws: XcodeTestInventoryError.codec(.unknownField("undocumented"))) {
        try inventory.verifyExecution(Data(unknown.utf8), summary: summary)
    }
    let otherType = xcode27FailedExecution.replacingOccurrences(
        of: "\"nodeType\":\"Failure Message\"",
        with: "\"nodeType\":\"Opaque Failure\""
    )
    #expect(throws: XcodeTestInventoryError.invalidNode("Failure Message")) {
        try inventory.verifyExecution(Data(otherType.utf8), summary: summary)
    }
    let badLocation = xcode27FailedExecution.replacingOccurrences(
        of: "\"lineNumber\":10",
        with: "\"lineNumber\":0"
    )
    #expect(throws: XcodeTestInventoryError.invalidNode("sourceLocation")) {
        try inventory.verifyExecution(Data(badLocation.utf8), summary: summary)
    }
    let unknownLocation = xcode27FailedExecution.replacingOccurrences(
        of: "\"lineNumber\":10",
        with: "\"lineNumber\":10,\"hidden\":true"
    )
    #expect(throws: XcodeTestInventoryError.codec(.unknownField("hidden"))) {
        try inventory.verifyExecution(Data(unknownLocation.utf8), summary: summary)
    }
    let otherMessage = xcode27FailedExecution.replacingOccurrences(
        of: "\"name\":\"assertion failed\"",
        with: "\"name\":\"different failure\""
    )
    #expect(throws: XcodeTestInventoryError.failureIdentityMismatch) {
        try inventory.verifyExecution(Data(otherMessage.utf8), summary: summary)
    }
    let repeatedMessage = xcode27FailedExecution.replacingOccurrences(
        of: "\"sourceLocation\":{\"filePath\":\"/tmp/SmokeTests.swift\",\"lineNumber\":10}}]",
        with: "\"sourceLocation\":{\"filePath\":\"/tmp/SmokeTests.swift\",\"lineNumber\":10}},{\"name\":\"assertion failed\",\"nodeType\":\"Failure Message\",\"sourceLocation\":{\"filePath\":\"/tmp/SmokeTests.swift\",\"lineNumber\":10}}]"
    )
    #expect(throws: XcodeTestInventoryError.failureIdentityMismatch) {
        try inventory.verifyExecution(Data(repeatedMessage.utf8), summary: summary)
    }
}
