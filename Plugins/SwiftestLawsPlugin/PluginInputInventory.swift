import Foundation

enum PluginInputInventoryError: Error {
    case unreadable(String)
    case unsupportedEntry(String)
}

struct PluginInputFile {
    let relativePath: String
    let url: URL
}

enum PluginInputInventory {
    static func collect(root: URL) throws -> [PluginInputFile] {
        var files: [PluginInputFile] = []
        try walk(directory: root, relativePath: "", files: &files)
        return files.sorted { $0.relativePath < $1.relativePath }
    }

    private static func walk(
        directory: URL,
        relativePath: String,
        files: inout [PluginInputFile]
    ) throws {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
        } catch {
            throw PluginInputInventoryError.unreadable(relativePath)
        }
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let relative = relativePath.isEmpty
                ? entry.lastPathComponent
                : relativePath + "/" + entry.lastPathComponent
            let values: URLResourceValues
            do {
                values = try entry.resourceValues(forKeys: [
                    .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
                ])
            } catch {
                throw PluginInputInventoryError.unreadable(relative)
            }
            if values.isSymbolicLink == true {
                throw PluginInputInventoryError.unsupportedEntry(relative)
            }
            if values.isDirectory == true {
                if !ignoredDirectory(relative) {
                    try walk(
                        directory: entry,
                        relativePath: relative,
                        files: &files
                    )
                }
            } else if values.isRegularFile == true {
                files.append(PluginInputFile(relativePath: relative, url: entry))
            } else {
                throw PluginInputInventoryError.unsupportedEntry(relative)
            }
        }
    }

    private static func ignoredDirectory(_ relative: String) -> Bool {
        relative == ".git"
            || relative == ".build"
            || relative == ".swiftpm"
            || relative == ".lake"
            || relative == ".local-signing"
            || relative == "DerivedData"
            || relative == "dist"
    }
}
