import Foundation
import SwiftestCodec
import SwiftestPlatform

public enum LeanTrustError: Error, Equatable, Sendable {
    case platform(PlatformError)
    case unexpectedEntry(String)
    case invalidUTF8(String)
    case unterminatedString(String)
    case unterminatedComment(String)
    case unterminatedQuotedIdentifier(String)
    case proofHole(SourceLocation, String)
    case lakeConfiguration(String)
    case lakeManifestCodec(StrictJSONError)
    case lakeManifestMismatch
}

public enum LeanTrust {
    private static let lakeConfiguration = "name = \"swiftest\"\n"
        + "version = \"0.1.0\"\n"
        + "defaultTargets = [\"SwiftestProofs\", \"swiftest-proof-oracle\"]\n"
        + "\n"
        + "[[lean_lib]]\n"
        + "name = \"SwiftestProofs\"\n"
        + "\n"
        + "[[lean_exe]]\n"
        + "name = \"swiftest-proof-oracle\"\n"
        + "root = \"SwiftestProofs.Oracle\"\n"
    private static let leanToolchain = "leanprover/lean4:v4.34.1\n"

    public static func audit(root: String) throws(LeanTrustError) {
        try auditConfiguration(root: root)
        try inspectFile(root: root, relative: "SwiftestProofs.lean")
        try inspectDirectory(root: root, relative: "SwiftestProofs")
    }

    static func auditManifest(root: String) throws(LeanTrustError) {
        let data = try readFile(root: root, relative: "lake-manifest.json")
        let document: JSONValue
        do {
            document = try StrictJSON.decode(data)
        } catch let error {
            throw .lakeManifestCodec(error)
        }
        let expected: JSONValue = .object([
            "version": .string("1.2.0"),
            "packagesDir": .string(".lake/packages"),
            "packages": .array([]),
            "name": .string("swiftest"),
            "lakeDir": .string(".lake"),
            "fixedToolchain": .boolean(false),
        ])
        guard document == expected else {
            throw .lakeManifestMismatch
        }
    }

    private static func auditConfiguration(root: String) throws(LeanTrustError) {
        let lakefile = try readFile(root: root, relative: "lakefile.toml")
        guard lakefile == Data(lakeConfiguration.utf8) else {
            throw .lakeConfiguration("lakefile.toml")
        }
        let toolchain = try readFile(root: root, relative: "lean-toolchain")
        guard toolchain == Data(leanToolchain.utf8) else {
            throw .lakeConfiguration("lean-toolchain")
        }
    }

    static func inspectSource(_ source: String, path: String) throws(LeanTrustError) {
        let bytes = Array(source.utf8)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            let next = index + 1 < bytes.count ? bytes[index + 1] : 0
            if byte == 34 {
                index += 1
                var closed = false
                while index < bytes.count {
                    if bytes[index] == 92 {
                        index += min(2, bytes.count - index)
                    } else if bytes[index] == 34 {
                        index += 1
                        closed = true
                        break
                    } else {
                        index += 1
                    }
                }
                if !closed {
                    throw .unterminatedString(path)
                }
                continue
            }
            if byte == 45 && next == 45 {
                while index < bytes.count && bytes[index] != 10 {
                    index += 1
                }
                continue
            }
            if byte == 47 && next == 45 {
                index += 2
                var depth = 1
                while index < bytes.count && depth > 0 {
                    let current = bytes[index]
                    let following = index + 1 < bytes.count ? bytes[index + 1] : 0
                    if current == 47 && following == 45 {
                        depth += 1
                        index += 2
                    } else if current == 45 && following == 47 {
                        depth -= 1
                        index += 2
                    } else {
                        index += 1
                    }
                }
                if depth != 0 {
                    throw .unterminatedComment(path)
                }
                continue
            }
            if byte == 0xC2 && next == 0xAB {
                index += 2
                var closed = false
                while index + 1 < bytes.count {
                    if bytes[index] == 0xC2 && bytes[index + 1] == 0xBB {
                        index += 2
                        closed = true
                        break
                    }
                    index += 1
                }
                if !closed {
                    throw .unterminatedQuotedIdentifier(path)
                }
                continue
            }
            if identifierByte(byte) {
                let start = index
                while index < bytes.count && identifierByte(bytes[index]) {
                    index += 1
                }
                let token = String(decoding: bytes[start..<index], as: UTF8.self)
                if token == "sorry" || token == "admit" || token == "axiom" || token == "sorryAx" {
                    throw .proofHole(location(path: path, bytes: bytes, offset: start), token)
                }
                continue
            }
            index += 1
        }
    }

    private static func inspectDirectory(root: String, relative: String) throws(LeanTrustError) {
        let path = root + "/" + relative
        let kind: FileEntryKind
        do {
            kind = try FileSystemBoundary.entryKind(path: path)
        } catch let error {
            throw .platform(error)
        }
        guard kind == .directory else {
            throw .unexpectedEntry(relative)
        }
        let entries: [String]
        do {
            entries = try FileSystemBoundary.list(path: path)
        } catch let error {
            throw .platform(error)
        }
        for entry in entries {
            let child = relative + "/" + entry
            let childKind: FileEntryKind
            do {
                childKind = try FileSystemBoundary.entryKind(path: root + "/" + child)
            } catch let error {
                throw .platform(error)
            }
            switch childKind {
            case .file:
                guard child.hasSuffix(".lean") else {
                    throw .unexpectedEntry(child)
                }
                try inspectFile(root: root, relative: child)
            case .directory:
                try inspectDirectory(root: root, relative: child)
            case .symbolicLink, .other:
                throw .unexpectedEntry(child)
            }
        }
    }

    private static func inspectFile(root: String, relative: String) throws(LeanTrustError) {
        let data = try readFile(root: root, relative: relative)
        guard let source = String(data: data, encoding: .utf8) else {
            throw .invalidUTF8(relative)
        }
        try inspectSource(source, path: relative)
    }

    private static func readFile(root: String, relative: String) throws(LeanTrustError) -> Data {
        let path = root + "/" + relative
        let kind: FileEntryKind
        do {
            kind = try FileSystemBoundary.entryKind(path: path)
        } catch let error {
            throw .platform(error)
        }
        guard kind == .file else {
            throw .unexpectedEntry(relative)
        }
        do {
            return try FileSystemBoundary.read(path: path)
        } catch let error {
            throw .platform(error)
        }
    }

    private static func identifierByte(_ byte: UInt8) -> Bool {
        (byte >= 65 && byte <= 90)
            || (byte >= 97 && byte <= 122)
            || (byte >= 48 && byte <= 57)
            || byte == 95
            || byte == 39
            || byte >= 128
    }

    private static func location(path: String, bytes: [UInt8], offset: Int) -> SourceLocation {
        var line = 1
        var column = 1
        for byte in bytes[0..<offset] {
            if byte == 10 {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }
        return SourceLocation(file: path, line: line, column: column)
    }
}
