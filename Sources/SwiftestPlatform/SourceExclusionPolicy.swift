public enum SourceExcludedDirectory: String, CaseIterable, Sendable {
    case gitMetadata = ".git"
    case swiftBuild = ".build"
    case leanBuild = ".lake"
    case localSigning = ".local-signing"
    case swiftConfiguration = ".swiftpm"
    case xcodeBuild = "DerivedData"
    case distribution = "dist"
}

public enum SourceExclusionPolicy {
    public static func excludesDirectory(relativePath: String) -> Bool {
        SourceExcludedDirectory(rawValue: relativePath) != nil
    }
}
