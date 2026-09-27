@testable import SwiftestEngine
import SwiftestModel
import SwiftestPlatform
import Testing

private func destinationDevice(
    id: String = "00006050-001A19043E07401C",
    name: String = "My Mac",
    platform: String = "macOS",
    osVersion: String = "27.0"
) throws -> XcodeDeviceIdentity {
    try .decode(.object([
        "deviceId": .string(id),
        "deviceName": .string(name),
        "architecture": .string("arm64e"),
        "modelName": .string("MacBook Pro"),
        "platform": .string(platform),
        "osVersion": .string(osVersion),
        "osBuildNumber": .string("26A428"),
    ]))
}

@Test
func xcodeDestinationCanonicalizesAndBindsMacIdentity() throws {
    let destination = try XcodeDestination.parse(
        "OS=27.0,name=My Mac,id=00006050-001A19043E07401C,platform=macOS"
    )
    #expect(destination.rawValue == "platform=macOS,id=00006050-001A19043E07401C,name=My Mac,OS=27.0")
    try destination.verify(device: destinationDevice())
}

@Test
func xcodeDestinationRejectsUnknownDuplicateAndDynamicSpecifiers() {
    #expect(throws: XcodeDestinationError.duplicateKey("id")) {
        try XcodeDestination.parse("platform=macOS,id=1,id=2")
    }
    #expect(throws: XcodeDestinationError.unknownKey("arch")) {
        try XcodeDestination.parse("platform=macOS,id=1,arch=arm64")
    }
    #expect(throws: XcodeDestinationError.missingKey("id")) {
        try XcodeDestination.parse("platform=macOS,name=My Mac")
    }
    #expect(throws: XcodeDestinationError.invalidValue("OS")) {
        try XcodeDestination.parse("platform=macOS,id=1,OS=latest")
    }
    #expect(throws: XcodeDestinationError.invalidValue("name")) {
        try XcodeDestination.parse("platform=macOS,id=1,name=$(HOST)")
    }
    #expect(throws: XcodeDestinationError.malformed("id=a=b")) {
        try XcodeDestination.parse("platform=macOS,id=a=b")
    }
    #expect(throws: XcodeDestinationError.unsupportedPlatform("unknown")) {
        try XcodeDestination.parse("platform=unknown,id=1")
    }
}

@Test
func xcodeDestinationRejectsObservedDeviceDrift() throws {
    let destination = try XcodeDestination.parse(
        "platform=macOS,id=00006050-001A19043E07401C,name=My Mac,OS=27.0"
    )
    #expect(throws: XcodeDestinationError.deviceMismatch("platform")) {
        try destination.verify(device: destinationDevice(platform: "iOS Simulator"))
    }
    #expect(throws: XcodeDestinationError.deviceMismatch("id")) {
        try destination.verify(device: destinationDevice(id: "OTHER-1"))
    }
    #expect(throws: XcodeDestinationError.deviceMismatch("name")) {
        try destination.verify(device: destinationDevice(name: "Other Mac"))
    }
    #expect(throws: XcodeDestinationError.deviceMismatch("OS")) {
        try destination.verify(device: destinationDevice(osVersion: "27.1"))
    }
}

@Test
func xcodeDestinationBindsSimulatorIdentityOnlyWhenExplicit() throws {
    let destination = try XcodeDestination.parse(
        "platform=iOS Simulator,id=ABCDEF12-3456-7890-ABCD-EF1234567890,name=iPhone,OS=27.0"
    )
    try destination.verify(device: destinationDevice(
        id: "ABCDEF12-3456-7890-ABCD-EF1234567890",
        name: "iPhone",
        platform: "iOS Simulator"
    ))
}

@Test
func xcodeAppDriverRejectsNonMacDestinationBeforeBuild() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-xcode-nonmac-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    try FileSystemBoundary.createDirectory(
        relativePath: ArtifactPath.parse("Smoke.xcodeproj"),
        capability: scratch.issueWriteCapability()
    )
    let container = try XcodeContainer.project(scratch.path + "/Smoke.xcodeproj")
    #expect(throws: XcodeAppTestError.unsupportedDestination) {
        try XcodeAppTestDriver.run(
            container: container,
            scheme: "Smoke",
            destination: "platform=iOS Simulator,id=ABCDEF12-3456-7890-ABCD-EF1234567890",
            workingDirectory: scratch.path,
            scratchParent: scratch.path
        )
    }
    #expect(Set(try FileSystemBoundary.list(path: scratch.path)) == ["Smoke.xcodeproj"])
}
