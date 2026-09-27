import Foundation
import SwiftestPlatform

enum XcodeCompiledSourceSetError: Error, Equatable, Sendable {
    case invalidRoot(String)
    case empty
    case invalidSource(String)
    case unreadableSource(String)
    case outsideRepository(String)
    case duplicateSource(String)
}

struct XcodeCompiledSourceSet: Equatable, Sendable {
    let paths: Set<String>

    private init(paths: Set<String>) {
        self.paths = paths
    }

    var sortedPaths: [String] {
        paths.sorted()
    }

    static func capture(
        _ candidates: [String],
        repositoryRoot: String
    ) throws(XcodeCompiledSourceSetError) -> XcodeCompiledSourceSet {
        guard !candidates.isEmpty else {
            throw .empty
        }
        let root: String
        do {
            root = try CanonicalPathBoundary.existing(repositoryRoot)
            guard try FileSystemBoundary.entryKind(path: repositoryRoot) == .directory else {
                throw XcodeCompiledSourceSetError.invalidRoot(repositoryRoot)
            }
        } catch {
            throw .invalidRoot(repositoryRoot)
        }
        let prefix = root + "/"
        var paths: Set<String> = []
        for candidate in candidates {
            let components = candidate.split(separator: "/", omittingEmptySubsequences: false)
            guard components.first == "", components.count > 1,
                components.dropFirst().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                candidate.hasSuffix(".swift"), !candidate.utf8.contains(0),
                !candidate.contains("$") else {
                throw .invalidSource(candidate)
            }
            let parent = URL(fileURLWithPath: candidate).deletingLastPathComponent().path
            let canonicalParent: String
            do {
                canonicalParent = try CanonicalPathBoundary.existing(parent)
            } catch {
                throw .unreadableSource(candidate)
            }
            guard (canonicalParent + "/" + URL(fileURLWithPath: candidate).lastPathComponent)
                .hasPrefix(prefix) else {
                throw .outsideRepository(candidate)
            }
            let kind: FileEntryKind
            do {
                kind = try FileSystemBoundary.entryKind(path: candidate)
            } catch {
                throw .unreadableSource(candidate)
            }
            guard kind == .file else {
                throw .invalidSource(candidate)
            }
            let canonical: String
            do {
                canonical = try CanonicalPathBoundary.existing(candidate)
            } catch {
                throw .unreadableSource(candidate)
            }
            guard canonical.hasPrefix(prefix) else {
                throw .outsideRepository(candidate)
            }
            let relative = String(canonical.dropFirst(prefix.count))
            guard !relative.split(separator: "/").contains(where: {
                SourceExclusionPolicy.excludesDirectory(relativePath: String($0))
            }) else {
                throw .outsideRepository(candidate)
            }
            guard paths.insert(canonical).inserted else {
                throw .duplicateSource(candidate)
            }
        }
        return XcodeCompiledSourceSet(paths: paths)
    }
}
