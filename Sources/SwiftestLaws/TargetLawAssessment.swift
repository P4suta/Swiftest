import SwiftestModel

public enum TargetLawGap: String, CaseIterable, Sendable {
    case incompleteRuleEvidence = "incomplete-rule-evidence"
    case manifestUnclassified = "manifest-unclassified"
    case sourceUnclassified = "source-unclassified"
    case swift6ModeUndeclared = "swift-6-mode-undeclared"
    case macroExpansionUninspected = "macro-expansion-uninspected"
    case externalProofMissing = "external-proof-missing"
    case xcodeAssessmentUnavailable = "xcode-assessment-unavailable"
}

public enum TargetLawStatus: Equatable, Sendable {
    case passed
    case violated
    case unassessed(TargetLawGap)
}

public struct TargetLawFinding: Equatable, Sendable {
    public let code: LawCode
    public let status: TargetLawStatus

    public init(code: LawCode, status: TargetLawStatus) {
        self.code = code
        self.status = status
    }
}

public struct TargetLawAssessment: Equatable, Sendable {
    public let report: LawReport
    public let findings: [TargetLawFinding]

    init(
        report: LawReport,
        checked: Set<LawCode>,
        defaultGap: TargetLawGap,
        specificGaps: [LawCode: TargetLawGap]
    ) {
        self.report = report
        let violated = Set(report.violations.map(\.law))
        self.findings = LawCode.allCases.map { code in
            let status: TargetLawStatus
            if violated.contains(code) {
                status = .violated
            } else if checked.contains(code) {
                status = .passed
            } else {
                if let gap = specificGaps[code] {
                    status = .unassessed(gap)
                } else {
                    status = .unassessed(defaultGap)
                }
            }
            return TargetLawFinding(code: code, status: status)
        }
    }

    public var lawObservations: [LawObservation] {
        findings.map { finding in
            switch finding.status {
            case .passed:
                LawObservation(code: finding.code, status: .passed)
            case .violated:
                LawObservation(
                    code: finding.code,
                    status: .failed,
                    diagnostic: Diagnostic(
                        code: .lawViolated,
                        subject: finding.code.rawValue,
                        detail: "external target law violation"
                    )
                )
            case .unassessed(let gap):
                LawObservation(
                    code: finding.code,
                    status: .failed,
                    diagnostic: Diagnostic(
                        code: .missingEvidence,
                        subject: finding.code.rawValue,
                        detail: gap.rawValue
                    )
                )
            }
        }
    }

    public var unassessedDiagnostics: [Diagnostic] {
        lawObservations.compactMap { observation in
            observation.diagnostic?.code == .missingEvidence ? observation.diagnostic : nil
        }
    }

    public static func unassessedExternalXcode() -> TargetLawAssessment {
        TargetLawAssessment(
            report: LawReport(checkedFiles: .zero, violations: []),
            checked: [],
            defaultGap: .xcodeAssessmentUnavailable,
            specificGaps: [:]
        )
    }
}
