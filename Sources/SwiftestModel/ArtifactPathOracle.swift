public enum ArtifactPathOracle {
    public static func text() -> String {
        let samples: [(String, String)] = [
            ("empty", ""),
            ("absolute", "/a"),
            ("nul", "a\u{0000}b"),
            ("parent", "a/../b"),
            ("self", "a/./b"),
            ("empty-segment", "a//b"),
            ("trailing", "a/"),
            ("relative", "a/b"),
            ("plain", "a"),
        ]
        let lines = samples.map { label, input in
            let outcome: String
            do {
                let path = try ArtifactPath.parse(input)
                outcome = path.rawValue == input ? "accepted" : "mismatch"
            } catch let error as ArtifactPathError {
                switch error {
                case .empty:
                    outcome = "empty"
                case .absolute:
                    outcome = "absolute"
                case .nul:
                    outcome = "nul"
                case .parentTraversal:
                    outcome = "parent-traversal"
                case .selfTraversal:
                    outcome = "self-traversal"
                case .emptySegment:
                    outcome = "empty-segment"
                }
            } catch {
                outcome = "unexpected-error"
            }
            return ["path", label, outcome].joined(separator: "\t")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
