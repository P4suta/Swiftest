import Foundation
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax
import SwiftestModel
import SwiftestPlatform

public enum LawScanner {
    private static let vnodeABIRelativePath = "Sources/" + AuditedBoundary.platformABI.rawValue
    private static let catalogModelPath = "Sources/SwiftestModel/Evidence.swift"
    private static let catalogClaimsPath = "Sources/SwiftestModel/Claims.swift"
    private static let catalogWorldPath = "Sources/SwiftestModel/World.swift"
    private static let catalogReportPath = "Sources/SwiftestReport/AssuredReport.swift"
    private static let worldSpacePath = "Sources/SwiftestEngine/WorldSpace.swift"
    private static let eventLeasePath = "Sources/SwiftestPlatform/FileEventLease.swift"
    private static let commandPath = "Sources/SwiftestCLI/SwiftestCommand.swift"
    private static let swiftPackageCampaignPath = "Sources/SwiftestEngine/SwiftPackageBoundaryFaultCampaign.swift"

    public static func scan(root: String) throws(LawScannerError) -> LawReport {
        try scan(root: root, inputClosure: .unrestricted)
    }

    public static func scan(
        root: String,
        declaredInputs: [String]
    ) throws(LawScannerError) -> LawReport {
        try scan(root: root, inputClosure: .declared(declaredInputs))
    }

    public static func scanExternalSwiftPackage(
        root: String
    ) throws(LawScannerError) -> TargetLawAssessment {
        let normalizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
        if normalizedRoot.isEmpty {
            throw .invalidRoot(root)
        }
        let inventory = sourceFiles(root: normalizedRoot)
        var violations = inventory.violations
        var manifest: ExternalPackageManifest?
        var importsByPath: [String: Set<String>] = [:]
        for path in inventory.paths {
            let relative = relativePath(path, root: normalizedRoot)
            guard relative == "Package.swift"
                || ((relative.hasPrefix("Sources/") || relative.hasPrefix("Tests/"))
                    && relative.hasSuffix(".swift")) else {
                violations.append(violation(.unclassifiedSource, file: relative, subject: "external-package-file"))
                continue
            }
            let data: Data
            do {
                data = try FileSystemBoundary.read(path: path)
            } catch {
                violations.append(violation(.unreadableSource, file: relative, subject: "read"))
                continue
            }
            guard let source = String(data: data, encoding: .utf8) else {
                violations.append(violation(.unreadableSource, file: relative, subject: "utf8"))
                continue
            }
            violations.append(contentsOf: scanSwiftSource(source, path: relative, boundaryPolicy: .externalTarget))
            if relative == "Package.swift" {
                manifest = ExternalPackageManifest.parse(source)
                if manifest == nil {
                    violations.append(violation(.unclassifiedTarget, file: relative, subject: "static-manifest"))
                }
            } else {
                importsByPath[relative] = importedModules(source)
            }
        }
        if !inventory.paths.contains(normalizedRoot + "/Package.swift") {
            violations.append(violation(.unclassifiedTarget, file: "Package.swift", subject: "missing-manifest"))
        }
        if let manifest {
            violations.append(contentsOf: validateExternalModuleGraph(
                manifest: manifest,
                importsByPath: importsByPath,
                root: normalizedRoot
            ))
        }
        let report = try makeReport(paths: inventory.paths, violations: violations)
        var checked: Set<LawCode> = [.unreadableSource, .unclassifiedSource]
        let manifestClosed = manifest != nil && !report.violations.contains { $0.law == .unclassifiedTarget }
        let sourceClosed = manifestClosed
            && inventory.paths.contains(where: {
                let relative = relativePath($0, root: normalizedRoot)
                return relative != "Package.swift" && relative.hasSuffix(".swift")
            })
            && !report.violations.contains {
                $0.law == .unreadableSource || $0.law == .unclassifiedSource
            }
        if sourceClosed {
            checked.insert(.forbiddenComment)
        }
        if sourceClosed && manifestClosed {
            checked.formUnion([
                .unclassifiedTarget, .forbiddenDependency, .reverseDependency, .testSupportImport,
            ])
        }
        var specificGaps: [LawCode: TargetLawGap] = [
            .uninspectedMacro: .macroExpansionUninspected,
            .missingExternalProof: .externalProofMissing,
        ]
        if !sourceClosed {
            specificGaps[.forbiddenComment] = manifestClosed ? .sourceUnclassified : .manifestUnclassified
        }
        if !manifestClosed {
            for code in [LawCode.unclassifiedTarget, .forbiddenDependency, .reverseDependency, .testSupportImport] {
                specificGaps[code] = .manifestUnclassified
            }
        }
        if let manifest, manifest.languageMode == .undeclared {
            specificGaps[.toolchainMismatch] = .swift6ModeUndeclared
        }
        return TargetLawAssessment(
            report: report,
            checked: checked,
            defaultGap: .incompleteRuleEvidence,
            specificGaps: specificGaps
        )
    }

    private enum InputClosure {
        case unrestricted
        case declared([String])
    }

    private static func scan(
        root: String,
        inputClosure: InputClosure
    ) throws(LawScannerError) -> LawReport {
        let normalizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
        if normalizedRoot.isEmpty {
            throw .invalidRoot(root)
        }
        let inventory = sourceFiles(root: normalizedRoot)
        let paths = inventory.paths
        var violations = inventory.violations
        switch inputClosure {
        case .unrestricted:
            break
        case .declared(let inputs):
            let discovered = Set(paths.map { relativePath($0, root: normalizedRoot) })
            let declared = Set(inputs)
            if declared.count != inputs.count {
                violations.append(violation(
                    .unclassifiedSource,
                    file: "Plugins/SwiftestLawsPlugin",
                    subject: "duplicate-plugin-input"
                ))
            }
            for relative in discovered.symmetricDifference(declared).sorted() {
                violations.append(violation(
                    .unclassifiedSource,
                    file: relative,
                    subject: "plugin-input-closure"
                ))
            }
        }
        if !paths.contains(normalizedRoot + "/" + vnodeABIRelativePath) {
            violations.append(violation(
                .vnodeEventProtocol,
                file: vnodeABIRelativePath,
                subject: "registration-source-missing"
            ))
        }
        if !paths.contains(normalizedRoot + "/" + eventLeasePath) {
            violations.append(violation(
                .eventGenerationWitness,
                file: eventLeasePath,
                subject: "event-lease-source-missing"
            ))
        }
        if !paths.contains(normalizedRoot + "/" + commandPath) {
            violations.append(violation(
                .eventGenerationWitness,
                file: commandPath,
                subject: "prepublication-source-missing"
            ))
        }
        if !paths.contains(normalizedRoot + "/" + swiftPackageCampaignPath) {
            violations.append(violation(
                .faultObservationProvenance,
                file: swiftPackageCampaignPath,
                subject: "campaign-source-missing"
            ))
        }
        var catalogModelSource: String?
        var catalogClaimsSource: String?
        var catalogWorldSource: String?
        var catalogReportSource: String?
        var worldSpaceSource: String?
        var importsByPath: [String: Set<String>] = [:]
        for path in paths {
            let relative = relativePath(path, root: normalizedRoot)
            if relative.hasSuffix(".md") || relative.hasSuffix(".markdown") {
                violations.append(violation(.handwrittenDocumentation, file: relative, subject: "markdown"))
                continue
            }
            if !shouldScan(relative) {
                violations.append(violation(.unclassifiedSource, file: relative, subject: "file"))
                continue
            }
            let data: Data
            do {
                data = try FileSystemBoundary.read(path: path)
            } catch {
                violations.append(violation(.unreadableSource, file: relative, subject: "read"))
                continue
            }
            guard let source = String(data: data, encoding: .utf8) else {
                violations.append(violation(.unreadableSource, file: relative, subject: "utf8"))
                continue
            }
            violations.append(contentsOf: scanFile(relativePath: relative, source: source, data: data))
            if relative == catalogModelPath {
                catalogModelSource = source
            } else if relative == catalogClaimsPath {
                catalogClaimsSource = source
            } else if relative == catalogWorldPath {
                catalogWorldSource = source
            } else if relative == catalogReportPath {
                catalogReportSource = source
            } else if relative == worldSpacePath {
                worldSpaceSource = source
            }
            if relative.hasSuffix(".swift") {
                importsByPath[relative] = importedModules(source)
            }
        }
        if let catalogModelSource, let catalogClaimsSource, let catalogWorldSource, let catalogReportSource {
            violations.append(contentsOf: catalogSerializationViolations(
                modelSource: catalogModelSource + "\n" + catalogClaimsSource + "\n" + catalogWorldSource,
                reportSource: catalogReportSource
            ))
        } else {
            if catalogModelSource == nil {
                violations.append(violation(
                    .catalogSerialization,
                    file: catalogModelPath,
                    subject: "model-source-missing"
                ))
            }
            if catalogReportSource == nil {
                violations.append(violation(
                    .catalogSerialization,
                    file: catalogReportPath,
                    subject: "serializer-source-missing"
                ))
            }
            if catalogClaimsSource == nil {
                violations.append(violation(
                    .catalogSerialization,
                    file: catalogClaimsPath,
                    subject: "claims-model-source-missing"
                ))
            }
            if catalogWorldSource == nil {
                violations.append(violation(
                    .catalogSerialization,
                    file: catalogWorldPath,
                    subject: "world-model-source-missing"
                ))
            }
        }
        if let catalogWorldSource, let worldSpaceSource {
            violations.append(contentsOf: worldSpaceAxisViolations(
                worldSource: catalogWorldSource,
                worldSpaceSource: worldSpaceSource
            ))
        } else if worldSpaceSource == nil {
            violations.append(violation(
                .catalogSerialization,
                file: worldSpacePath,
                subject: "world-space-source-missing"
            ))
        }
        violations.append(contentsOf: validateModuleGraph(importsByPath: importsByPath, root: normalizedRoot))
        return try makeReport(paths: paths, violations: violations)
    }

    private static func makeReport(
        paths: [String],
        violations: [LawViolation]
    ) throws(LawScannerError) -> LawReport {
        let count: EvidenceCount
        do {
            count = try .nonnegative(paths.count)
        } catch let error {
            throw .count(error)
        }
        let sorted = violations.sorted {
            if $0.location.file != $1.location.file {
                return $0.location.file < $1.location.file
            }
            if $0.location.line != $1.location.line {
                return $0.location.line < $1.location.line
            }
            if $0.location.column != $1.location.column {
                return $0.location.column < $1.location.column
            }
            if $0.law.rawValue != $1.law.rawValue {
                return $0.law.rawValue < $1.law.rawValue
            }
            return $0.subject < $1.subject
        }
        return LawReport(checkedFiles: count, violations: sorted)
    }

    public static func scanSwiftSource(
        _ source: String,
        path: String
    ) -> [LawViolation] {
        scanSwiftSource(
            source,
            path: path,
            boundaryPolicy: .swiftestRepository,
            vnodeRequirement: .fragment
        )
    }

    private enum BoundaryPolicy {
        case swiftestRepository
        case externalTarget
    }

    private enum VnodeRegistrationRequirement {
        case fragment
        case completeABI
    }

    private static func scanSwiftSource(
        _ source: String,
        path: String,
        boundaryPolicy: BoundaryPolicy,
        vnodeRequirement: VnodeRegistrationRequirement = .fragment
    ) -> [LawViolation] {
        let tree = Parser.parse(source: source)
        var violations: [LawViolation] = []
        let parseDiagnostics = ParseDiagnosticsGenerator.diagnostics(for: tree)
        if !parseDiagnostics.isEmpty {
            violations.append(violation(.unreadableSource, file: path, subject: "parse"))
        }
        let tokens = Array(tree.tokens(viewMode: .sourceAccurate))
        for token in tokens {
            var leadingOffset = token.position.utf8Offset
            for trivia in token.leadingTrivia {
                if let text = commentText(trivia),
                    !isAllowedComment(text: text, path: path, source: source, offset: leadingOffset) {
                    violations.append(violation(
                        .forbiddenComment,
                        file: path,
                        source: source,
                        offset: leadingOffset,
                        subject: commentKind(text)
                    ))
                }
                leadingOffset += trivia.sourceLength.utf8Length
            }
            var trailingOffset = token.endPositionBeforeTrailingTrivia.utf8Offset
            for trivia in token.trailingTrivia {
                if let text = commentText(trivia) {
                    violations.append(violation(
                        .forbiddenComment,
                        file: path,
                        source: source,
                        offset: trailingOffset,
                        subject: commentKind(text)
                    ))
                }
                trailingOffset += trivia.sourceLength.utf8Length
            }
        }
        let records = tokens.compactMap { token -> TokenRecord? in
            if isLiteralMaterial(token.tokenKind) {
                return nil
            }
            return TokenRecord(
                text: token.text,
                offset: token.positionAfterSkippingLeadingTrivia.utf8Offset,
                isFileScope: isFileScope(token),
                isTypeStaticVar: isTypeStaticVar(token),
                isForceUnwrap: token.tokenKind == .exclamationMark
            )
        }
        violations.append(contentsOf: tokenViolations(
            records,
            source: source,
            path: path,
            boundaryPolicy: boundaryPolicy
        ))
        violations.append(contentsOf: vnodeEventViolations(
            tokens,
            source: source,
            path: path,
            boundaryPolicy: boundaryPolicy,
            requirement: vnodeRequirement
        ))
        violations.append(contentsOf: macroViolations(tokens, path: path, boundaryPolicy: boundaryPolicy))
        if path == swiftPackageCampaignPath {
            violations.append(contentsOf: swiftPackageFaultProvenanceViolations(tree, source: source, path: path))
        }
        return violations
    }

    private static func swiftPackageFaultProvenanceViolations(
        _ tree: SourceFileSyntax,
        source: String,
        path: String
    ) -> [LawViolation] {
        var issuanceCount = 0
        var consumptionCount = 0
        var directVerdictOffsets: [Int] = []
        func inspect(_ node: Syntax) {
            if let call = node.as(FunctionCallExprSyntax.self) {
                let called = codeTokens(call.calledExpression)
                if called == ["SwiftPackageTargetObserver", ".", "denialReceipt"] {
                    issuanceCount += 1
                }
                if called == ["FaultActivationObservation"] {
                    directVerdictOffsets.append(call.positionAfterSkippingLeadingTrivia.utf8Offset)
                }
            }
            if let statement = node.as(ReturnStmtSyntax.self),
                let call = statement.expression?.as(FunctionCallExprSyntax.self),
                codeTokens(call.calledExpression) == ["denialReceipt", ".", "close"] {
                consumptionCount += 1
            }
            if let access = node.as(MemberAccessExprSyntax.self),
                access.declName.baseName.text == "handled" || access.declName.baseName.text == "failedClosed" {
                directVerdictOffsets.append(access.positionAfterSkippingLeadingTrivia.utf8Offset)
            }
            for child in node.children(viewMode: .sourceAccurate) {
                inspect(child)
            }
        }
        inspect(Syntax(tree))
        var violations: [LawViolation] = []
        if issuanceCount != 2 {
            violations.append(violation(
                .faultObservationProvenance,
                file: path,
                subject: "denial-receipt-issuance"
            ))
        }
        if consumptionCount != 1 {
            violations.append(violation(
                .faultObservationProvenance,
                file: path,
                subject: "denial-receipt-consumption"
            ))
        }
        for offset in directVerdictOffsets {
            violations.append(violation(
                .faultObservationProvenance,
                file: path,
                source: source,
                offset: offset,
                subject: "direct-fault-verdict"
            ))
        }
        return violations
    }

    private static func scanFile(relativePath: String, source: String, data: Data) -> [LawViolation] {
        if relativePath.hasSuffix(".swift") {
            let requirement: VnodeRegistrationRequirement
            if relativePath == vnodeABIRelativePath {
                requirement = .completeABI
            } else {
                requirement = .fragment
            }
            let syntaxViolations = scanSwiftSource(
                source,
                path: relativePath,
                boundaryPolicy: .swiftestRepository,
                vnodeRequirement: requirement
            )
            if relativePath == eventLeasePath {
                return syntaxViolations + eventGenerationViolations(in: source)
            }
            if relativePath == commandPath {
                return syntaxViolations + eventPrepublicationViolations(in: source)
            }
            if relativePath == "Package.swift" {
                return syntaxViolations + PackageManifestGraph.violations(in: source)
            }
            return syntaxViolations
        }
        let flavor: SourceFlavor
        if relativePath.hasSuffix(".lean") {
            flavor = .lean
        } else if relativePath.hasSuffix(".json") {
            flavor = .json
        } else if relativePath.hasSuffix(".yml")
            || relativePath.hasSuffix(".yaml")
            || relativePath.hasSuffix(".toml")
            || relativePath == ".gitignore"
            || relativePath.hasPrefix("Scripts/")
            || relativePath.hasPrefix(".githooks/") {
            flavor = .hash
        } else {
            flavor = .plain
        }
        var violations: [LawViolation] = []
        if flavor == .json && !OtherSourceLexer.validatesJSON(data) {
            violations.append(violation(.unreadableSource, file: relativePath, subject: "json"))
        }
        let scan = OtherSourceLexer.scan(in: source, flavor: flavor)
        if let offset = scan.unsupportedLeanRawStringOffset {
            violations.append(violation(
                .unreadableSource,
                file: relativePath,
                source: source,
                offset: offset,
                subject: "lean-raw-string"
            ))
        }
        for comment in scan.comments {
            if isAllowedOtherComment(comment, path: relativePath) {
                continue
            }
            violations.append(violation(
                .forbiddenComment,
                file: relativePath,
                source: source,
                offset: comment.offset,
                subject: "comment"
            ))
        }
        return violations
    }

    private struct SerializedCatalogField {
        let name: String
        let dependencies: Set<String>
        let value: ExprSyntax
        let nested: [SerializedCatalogField]?
        let offset: Int
    }

    static func catalogSerializationViolations(
        modelSource: String,
        reportSource: String
    ) -> [LawViolation] {
        guard let properties = storedProperties(in: modelSource, named: "EvidenceCatalog"),
            let reviewProperties = storedProperties(in: modelSource, named: "IndependentReview") else {
            return [violation(
                .catalogSerialization,
                file: catalogModelPath,
                subject: "model-shape"
            )]
        }
        guard let fields = serializedCatalogFields(in: reportSource) else {
            return [violation(
                .catalogSerialization,
                file: catalogReportPath,
                subject: "serializer-shape"
            )]
        }
        let names = fields.map(\.name)
        let serialized = Set(names)
        var violations: [LawViolation] = []
        var seen = Set<String>()
        for field in fields {
            if !seen.insert(field.name).inserted {
                violations.append(violation(
                    .catalogSerialization,
                    file: catalogReportPath,
                    source: reportSource,
                    offset: field.offset,
                    subject: "duplicate:" + field.name
                ))
            }
            if field.dependencies != Set([field.name]) {
                violations.append(violation(
                    .catalogSerialization,
                    file: catalogReportPath,
                    source: reportSource,
                    offset: field.offset,
                    subject: "binding:" + field.name
                ))
            }
            if !directCatalogEncoding(field, modelSource: modelSource) {
                violations.append(violation(
                    .catalogSerialization,
                    file: catalogReportPath,
                    source: reportSource,
                    offset: field.offset,
                    subject: "transformation:" + field.name
                ))
            }
        }
        for missing in properties.subtracting(serialized).sorted() {
            violations.append(violation(
                .catalogSerialization,
                file: catalogReportPath,
                subject: "missing:" + missing
            ))
        }
        for extra in serialized.subtracting(properties).sorted() {
            violations.append(violation(
                .catalogSerialization,
                file: catalogReportPath,
                subject: "extra:" + extra
            ))
        }
        if let review = fields.first(where: { $0.name == "review" }),
            let nested = review.nested {
            violations.append(contentsOf: nestedCatalogViolations(
                nested,
                properties: reviewProperties,
                prefix: "review",
                root: "catalog",
                depth: 2,
                source: reportSource
            ))
        } else if serialized.contains("review") {
            violations.append(violation(
                .catalogSerialization,
                file: catalogReportPath,
                subject: "review-shape"
            ))
        }
        for field in fields {
            guard let elementType = storedArrayElementType(
                in: modelSource,
                owner: "EvidenceCatalog",
                property: field.name
            ),
                let elementProperties = storedProperties(in: modelSource, named: elementType) else {
                continue
            }
            guard let mapped = mappedObjectFields(
                in: field.value,
                property: field.name,
                elementType: elementType
            ) else {
                violations.append(violation(
                    .catalogSerialization,
                    file: catalogReportPath,
                    source: reportSource,
                    offset: field.offset,
                    subject: field.name + "-shape"
                ))
                continue
            }
            violations.append(contentsOf: nestedCatalogViolations(
                mapped.fields,
                properties: elementProperties,
                prefix: field.name,
                root: mapped.elementName,
                depth: 1,
                source: reportSource
            ))
        }
        if serialized.contains("failures") && !failureValueIsDirectlyBound(
            modelSource: modelSource,
            reportSource: reportSource
        ) {
            violations.append(violation(
                .catalogSerialization,
                file: catalogReportPath,
                subject: "failure-payload"
            ))
        }
        if serialized.contains("worlds"),
            storedPropertyType(in: modelSource, owner: "EvidenceCatalog", property: "worlds") == "DeclaredWorlds",
            !worldValueIsDirectlyBound(modelSource: modelSource, reportSource: reportSource) {
            violations.append(violation(
                .catalogSerialization,
                file: catalogReportPath,
                subject: "world-definition"
            ))
        }
        return violations
    }

    private static func nestedCatalogViolations(
        _ fields: [SerializedCatalogField],
        properties: Set<String>,
        prefix: String,
        root: String,
        depth: Int,
        source: String
    ) -> [LawViolation] {
        let names = Set(fields.map(\.name))
        var seen = Set<String>()
        var violations: [LawViolation] = []
        for field in fields {
            if !seen.insert(field.name).inserted {
                violations.append(violation(
                    .catalogSerialization,
                    file: catalogReportPath,
                    source: source,
                    offset: field.offset,
                    subject: prefix + "-duplicate:" + field.name
                ))
            }
            let expected = depth == 2 ? prefix + "." + field.name : field.name
            if memberPaths(in: Syntax(field.value), rootedAt: root, depth: depth) != Set([expected]) {
                violations.append(violation(
                    .catalogSerialization,
                    file: catalogReportPath,
                    source: source,
                    offset: field.offset,
                    subject: prefix + "-binding:" + field.name
                ))
            }
            let rawValueRequired = !(
                (prefix == "preservationClaims" || prefix == "detectionClaims")
                    && field.name == "name"
            )
            if !directScalarEncoding(
                field.value,
                root: root,
                property: depth == 2 ? prefix + "." + field.name : field.name,
                includesRawValue: rawValueRequired
            ) {
                violations.append(violation(
                    .catalogSerialization,
                    file: catalogReportPath,
                    source: source,
                    offset: field.offset,
                    subject: prefix + "-transformation:" + field.name
                ))
            }
        }
        for missing in properties.subtracting(names).sorted() {
            violations.append(violation(
                .catalogSerialization,
                file: catalogReportPath,
                subject: prefix + "-missing:" + missing
            ))
        }
        for extra in names.subtracting(properties).sorted() {
            violations.append(violation(
                .catalogSerialization,
                file: catalogReportPath,
                subject: prefix + "-extra:" + extra
            ))
        }
        return violations
    }

    private static func directCatalogEncoding(
        _ field: SerializedCatalogField,
        modelSource: String
    ) -> Bool {
        if field.name == "review" {
            return field.nested != nil
        }
        if field.name == "worlds",
            storedPropertyType(in: modelSource, owner: "EvidenceCatalog", property: "worlds") == "DeclaredWorlds" {
            return codeTokens(field.value) == [
                ".", "array", "(", "catalog", ".", "worlds", ".", "definitions", ".", "map",
                "(", "worldValue", ")", ")",
            ]
        }
        if directScalarEncoding(field.value, root: "catalog", property: field.name) {
            return true
        }
        let elementType = storedArrayElementType(
            in: modelSource,
            owner: "EvidenceCatalog",
            property: field.name
        )
        let mapPath = elementType == "Claim"
            ? ["catalog", ".", field.name, ".", "definitions", ".", "map"]
            : ["catalog", ".", field.name, ".", "map"]
        guard let array = field.value.as(FunctionCallExprSyntax.self),
            codeTokens(array.calledExpression) == [".", "array"],
            array.arguments.count == 1,
            let argument = array.arguments.first,
            let map = argument.expression.as(FunctionCallExprSyntax.self),
            codeTokens(map.calledExpression) == mapPath else {
            return false
        }
        if map.arguments.count == 1, map.trailingClosure == nil,
            let transformer = map.arguments.first,
            codeTokens(transformer.expression) == ["failureValue"],
            field.name == "failures" {
            return true
        }
        guard map.arguments.isEmpty, let closure = map.trailingClosure,
            closure.statements.count == 1 else {
            return false
        }
        if let elementType, storedProperties(in: modelSource, named: elementType) != nil {
            return mappedObjectFields(
                in: field.value,
                property: field.name,
                elementType: elementType
            ) != nil
        }
        guard closure.signature == nil, let statement = closure.statements.first,
            let expression = statement.item.as(ExprSyntax.self) else {
            return false
        }
        return directScalarEncoding(expression, root: "$0", property: "rawValue", includesRawValue: false)
    }

    private static func directScalarEncoding(
        _ expression: ExprSyntax,
        root: String,
        property: String,
        includesRawValue: Bool = true
    ) -> Bool {
        let path = [root] + property.split(separator: ".").flatMap { [".", String($0)] }
        let rawPath = includesRawValue ? path + [".", "rawValue"] : path
        let scalar = codeTokens(expression)
        return scalar == [".", "string", "("] + rawPath + [")"]
            || scalar == [".", "number", "(", "String", "("] + rawPath + [")", ")"]
            || scalar == ["digestValue", "("] + path + [")"]
            || scalar == ["diagnosticValue", "("] + path + [")"]
    }

    private static func enumCaseTypes(in source: String, named name: String) -> [String: [String]]? {
        let tree = Parser.parse(source: source)
        let declarations = tree.statements.compactMap { $0.item.as(EnumDeclSyntax.self) }
            .filter { $0.name.text == name }
        guard declarations.count == 1, let declaration = declarations.first else {
            return nil
        }
        var cases: [String: [String]] = [:]
        for member in declaration.memberBlock.members {
            guard let caseDeclaration = member.decl.as(EnumCaseDeclSyntax.self) else {
                continue
            }
            for element in caseDeclaration.elements {
                guard cases[element.name.text] == nil,
                    element.rawValue == nil,
                    let parameters = element.parameterClause?.parameters else {
                    return nil
                }
                var types: [String] = []
                for parameter in parameters {
                    guard parameter.firstName == nil,
                        parameter.secondName == nil,
                        parameter.defaultValue == nil,
                        let type = parameter.type.as(IdentifierTypeSyntax.self),
                        type.genericArgumentClause == nil else {
                        return nil
                    }
                    types.append(type.name.text)
                }
                cases[element.name.text] = types
            }
        }
        return cases.isEmpty ? nil : cases
    }

    private static func payloadKey(for type: String) -> String? {
        let stem = type.hasSuffix("ID") ? String(type.dropLast(2)) : type
        guard let first = stem.first else {
            return nil
        }
        return first.lowercased() + stem.dropFirst()
    }

    private static func failureCase(_ branch: SwitchCaseSyntax) -> (name: String, binders: [String])? {
        guard let label = branch.label.as(SwitchCaseLabelSyntax.self),
            label.caseItems.count == 1,
            let item = label.caseItems.first,
            item.whereClause == nil else {
            return nil
        }
        let tokens = codeTokens(item.pattern)
        guard tokens.count >= 2, tokens[0] == "." else {
            return nil
        }
        let name = tokens[1]
        if tokens.count == 2 {
            return (name, [])
        }
        guard tokens.count >= 6, tokens[2] == "(", tokens.last == ")" else {
            return nil
        }
        var binders: [String] = []
        var position = 3
        let end = tokens.count - 1
        while position < end {
            guard position + 1 < end, tokens[position] == "let" else {
                return nil
            }
            binders.append(tokens[position + 1])
            position += 2
            if position < end {
                guard tokens[position] == "," else {
                    return nil
                }
                position += 1
            }
        }
        guard position == end, binders.count == Set(binders).count else {
            return nil
        }
        return (name, binders)
    }

    private static func simpleStringLiteral(_ expression: ExprSyntax) -> String? {
        guard let literal = expression.as(StringLiteralExprSyntax.self),
            literal.openingPounds == nil,
            literal.openingQuote.text == "\"",
            literal.closingQuote.text == "\"",
            literal.segments.count == 1,
            let segment = literal.segments.first?.as(StringSegmentSyntax.self),
            !segment.content.text.isEmpty,
            !segment.content.text.contains("\\") else {
            return nil
        }
        return segment.content.text
    }

    private static func stringLiteral(in syntax: Syntax) -> String? {
        var literals: [StringLiteralExprSyntax] = []
        func collect(_ node: Syntax) {
            if let literal = node.as(StringLiteralExprSyntax.self) {
                literals.append(literal)
            }
            for child in node.children(viewMode: .sourceAccurate) {
                collect(child)
            }
        }
        collect(syntax)
        guard literals.count == 1, let literal = literals.first else {
            return nil
        }
        return simpleStringLiteral(ExprSyntax(literal))
    }

    private static func directFailureObject(
        in branch: SwitchCaseSyntax,
        binders: [String],
        types: [String],
        kinds: inout Set<String>
    ) -> Bool {
        guard binders.count == types.count,
            let statement = directStatements(in: branch, count: 1)?.first,
            let returned = statement.item.as(ReturnStmtSyntax.self),
            let expression = returned.expression,
            let fields = serializedObjectFields(in: expression) else {
            return false
        }
        let names = fields.map(\.name)
        guard names.count == Set(names).count,
            let kindField = fields.first(where: { $0.name == "kind" }),
            let kindCall = kindField.value.as(FunctionCallExprSyntax.self),
            codeTokens(kindCall.calledExpression) == [".", "string"],
            kindCall.arguments.count == 1,
            let kindArgument = kindCall.arguments.first,
            let kind = simpleStringLiteral(kindArgument.expression),
            kinds.insert(kind).inserted else {
            return false
        }
        var expected = Set(["kind"])
        for (binder, type) in zip(binders, types) {
            guard let key = payloadKey(for: type), key == binder,
                let field = fields.first(where: { $0.name == key }),
                codeTokens(field.value) == [".", "string", "(", binder, ".", "rawValue", ")"] else {
                return false
            }
            expected.insert(key)
        }
        return Set(names) == expected
    }

    private static func worldValueIsDirectlyBound(modelSource: String, reportSource: String) -> Bool {
        guard let cases = enumCaseTypes(in: modelSource, named: "DeclaredWorld"),
            cases == ["modeled": ["WorldDefinition"], "unmodeledHost": ["WorldID"]] else {
            return false
        }
        let tree = Parser.parse(source: reportSource)
        let owners = tree.statements.compactMap { $0.item.as(EnumDeclSyntax.self) }
            .filter { $0.name.text == "ReportCodec" }
        guard owners.count == 1, let owner = owners.first else {
            return false
        }
        let functions = owner.memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }
            .filter { $0.name.text == "worldValue" }
        guard functions.count == 1, let function = functions.first,
            function.signature.parameterClause.parameters.count == 1,
            let parameter = function.signature.parameterClause.parameters.first,
            parameter.secondName?.text == "declared",
            parameter.type.as(IdentifierTypeSyntax.self)?.name.text == "DeclaredWorld",
            let body = function.body,
            body.statements.count == 1,
            let statement = body.statements.first,
            let outer = statement.item.as(ExpressionStmtSyntax.self)?.expression.as(SwitchExprSyntax.self),
            codeTokens(outer.subject) == ["declared"] else {
            return false
        }
        var seen = Set<String>()
        for element in outer.cases {
            guard let branch = element.as(SwitchCaseSyntax.self),
                let parsed = failureCase(branch),
                seen.insert(parsed.name).inserted,
                parsed.binders.count == 1,
                let binder = parsed.binders.first,
                let returned = directStatements(in: branch, count: 1)?.first?.item.as(ReturnStmtSyntax.self),
                let expression = returned.expression,
                let fields = serializedObjectFields(in: expression),
                let kind = fields.first(where: { $0.name == "kind" }),
                let kindCall = kind.value.as(FunctionCallExprSyntax.self),
                codeTokens(kindCall.calledExpression) == [".", "string"],
                kindCall.arguments.count == 1,
                let literal = kindCall.arguments.first?.expression,
                simpleStringLiteral(literal) == (parsed.name == "modeled" ? "modeled" : "unmodeled-host") else {
                return false
            }
            switch parsed.name {
            case "modeled":
                guard directModeledWorld(fields, binder: binder, modelSource: modelSource) else {
                    return false
                }
            case "unmodeledHost":
                guard Set(fields.map(\.name)) == ["kind", "id"], fields.count == 2,
                    let id = fields.first(where: { $0.name == "id" }),
                    directScalarEncoding(id.value, root: binder, property: "rawValue", includesRawValue: false) else {
                    return false
                }
            default:
                return false
            }
        }
        return seen == Set(cases.keys)
    }

    private static func directModeledWorld(
        _ fields: [SerializedCatalogField],
        binder: String,
        modelSource: String
    ) -> Bool {
        guard let properties = storedProperties(in: modelSource, named: "WorldDefinition"),
            fields.count == properties.count + 1,
            Set(fields.map(\.name)) == properties.union(["kind"]) else {
            return false
        }
        for field in fields where field.name != "kind" {
            guard let type = storedPropertyType(in: modelSource, owner: "WorldDefinition", property: field.name) else {
                return false
            }
            if let nested = storedProperties(in: modelSource, named: type) {
                guard let nestedFields = serializedObjectFields(in: field.value),
                    nestedFields.count == nested.count,
                    Set(nestedFields.map(\.name)) == nested else {
                    return false
                }
                for nestedField in nestedFields {
                    guard let nestedType = storedPropertyType(
                        in: modelSource,
                        owner: type,
                        property: nestedField.name
                    ) else {
                        return false
                    }
                    let path = field.name + "." + nestedField.name
                    if nestedType == "[Int]" {
                        guard directIntegerArray(nestedField.value, root: binder, property: path) else {
                            return false
                        }
                    } else if !directScalarEncoding(nestedField.value, root: binder, property: path) {
                        return false
                    }
                }
            } else if !directScalarEncoding(field.value, root: binder, property: field.name) {
                return false
            }
        }
        return true
    }

    private static func directIntegerArray(_ expression: ExprSyntax, root: String, property: String) -> Bool {
        let path = [root] + property.split(separator: ".").flatMap { [".", String($0)] }
        guard let array = expression.as(FunctionCallExprSyntax.self),
            codeTokens(array.calledExpression) == [".", "array"],
            array.arguments.count == 1,
            let map = array.arguments.first?.expression.as(FunctionCallExprSyntax.self),
            codeTokens(map.calledExpression) == path + [".", "map"],
            map.arguments.isEmpty,
            let closure = map.trailingClosure,
            closure.signature == nil,
            closure.statements.count == 1,
            let item = closure.statements.first?.item.as(ExprSyntax.self),
            codeTokens(item) == [".", "number", "(", "String", "(", "$0", ")", ")"] else {
            return false
        }
        return true
    }

    private static func apparatusFailureObject(
        in branch: SwitchCaseSyntax,
        cases: [String: [String]],
        binder: String,
        kinds: inout Set<String>
    ) -> Bool {
        guard let statements = directStatements(in: branch, count: 4),
            codeTokens(statements[0]) == ["let", "kind", ":", "String"],
            codeTokens(statements[1]) == ["let", "diagnostic", ":", "Diagnostic"],
            let inner = statements[2].item.as(ExpressionStmtSyntax.self)?.expression.as(SwitchExprSyntax.self),
            codeTokens(inner.subject) == [binder],
            let returned = statements[3].item.as(ReturnStmtSyntax.self),
            let expression = returned.expression,
            let fields = serializedObjectFields(in: expression),
            fields.count == 2,
            let kindField = fields.first(where: { $0.name == "kind" }),
            let diagnosticField = fields.first(where: { $0.name == "diagnostic" }),
            codeTokens(kindField.value) == [".", "string", "(", "kind", ")"],
            codeTokens(diagnosticField.value) == ["diagnosticValue", "(", "diagnostic", ")"] else {
            return false
        }
        var seen = Set<String>()
        for element in inner.cases {
            guard let innerCase = element.as(SwitchCaseSyntax.self),
                let parsed = failureCase(innerCase),
                seen.insert(parsed.name).inserted,
                let types = cases[parsed.name], types.count == 1,
                payloadKey(for: types[0]) == "diagnostic",
                parsed.binders.count == 1,
                let statements = directStatements(in: innerCase, count: 2),
                codeTokens(statements[0]) == ["kind", "="],
                let kind = stringLiteral(in: Syntax(statements[0])),
                kinds.insert(kind).inserted,
                codeTokens(statements[1]) == ["diagnostic", "=", parsed.binders[0]] else {
                return false
            }
        }
        return seen == Set(cases.keys)
    }

    private static func failureValueIsDirectlyBound(modelSource: String, reportSource: String) -> Bool {
        guard let outerCases = enumCaseTypes(in: modelSource, named: "ExecutionFailure") else {
            return false
        }
        let tree = Parser.parse(source: reportSource)
        let owners = tree.statements.compactMap { $0.item.as(EnumDeclSyntax.self) }
            .filter { $0.name.text == "ReportCodec" }
        guard owners.count == 1, let owner = owners.first else {
            return false
        }
        let functions = owner.memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }
            .filter { $0.name.text == "failureValue" }
        guard functions.count == 1, let function = functions.first,
            function.signature.parameterClause.parameters.count == 1,
            let parameter = function.signature.parameterClause.parameters.first,
            parameter.secondName?.text == "failure",
            parameter.type.as(IdentifierTypeSyntax.self)?.name.text == "ExecutionFailure",
            let body = function.body,
            body.statements.count == 1,
            let statement = body.statements.first,
            let outer = statement.item.as(ExpressionStmtSyntax.self)?.expression.as(SwitchExprSyntax.self),
            codeTokens(outer.subject) == ["failure"] else {
            return false
        }
        var seenOuter = Set<String>()
        var kinds = Set<String>()
        for element in outer.cases {
            guard let branch = element.as(SwitchCaseSyntax.self),
                let parsed = failureCase(branch),
                seenOuter.insert(parsed.name).inserted,
                let types = outerCases[parsed.name], types.count == 1,
                parsed.binders.count == 1,
                let nestedCases = enumCaseTypes(in: modelSource, named: types[0]) else {
                return false
            }
            if parsed.name == "apparatus" {
                guard apparatusFailureObject(
                    in: branch,
                    cases: nestedCases,
                    binder: parsed.binders[0],
                    kinds: &kinds
                ) else {
                    return false
                }
                continue
            }
            guard let nestedStatement = directStatements(in: branch, count: 1)?.first,
                let nested = nestedStatement.item.as(ExpressionStmtSyntax.self)?.expression.as(SwitchExprSyntax.self),
                codeTokens(nested.subject) == [parsed.binders[0]] else {
                return false
            }
            var seenNested = Set<String>()
            for nestedElement in nested.cases {
                guard let nestedBranch = nestedElement.as(SwitchCaseSyntax.self),
                    let nestedPattern = failureCase(nestedBranch),
                    seenNested.insert(nestedPattern.name).inserted,
                    let payloadTypes = nestedCases[nestedPattern.name],
                    directFailureObject(
                        in: nestedBranch,
                        binders: nestedPattern.binders,
                        types: payloadTypes,
                        kinds: &kinds
                    ) else {
                    return false
                }
            }
            guard seenNested == Set(nestedCases.keys) else {
                return false
            }
        }
        return seenOuter == Set(outerCases.keys)
    }

    private static func storedProperties(in source: String, named name: String) -> Set<String>? {
        let tree = Parser.parse(source: source)
        let matches = tree.statements.compactMap { $0.item.as(StructDeclSyntax.self) }
            .filter { $0.name.text == name }
        guard matches.count == 1, let declaration = matches.first else {
            return nil
        }
        var names: [String] = []
        for member in declaration.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                !variable.modifiers.contains(where: {
                    $0.name.text == "static" || $0.name.text == "class"
                }) else {
                continue
            }
            for binding in variable.bindings {
                if let accessor = binding.accessorBlock {
                    if case .getter = accessor.accessors {
                        continue
                    }
                    return nil
                }
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                    return nil
                }
                names.append(identifier.identifier.text)
            }
        }
        guard !names.isEmpty, names.count == Set(names).count else {
            return nil
        }
        return Set(names)
    }

    private static func storedArrayElementType(
        in source: String,
        owner: String,
        property: String
    ) -> String? {
        let tree = Parser.parse(source: source)
        let matches = tree.statements.compactMap { $0.item.as(StructDeclSyntax.self) }
            .filter { $0.name.text == owner }
        guard matches.count == 1, let declaration = matches.first else {
            return nil
        }
        for member in declaration.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else {
                continue
            }
            for binding in variable.bindings where
                binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == property {
                guard let type = binding.typeAnnotation?.type else {
                    return nil
                }
                if let element = type.as(ArrayTypeSyntax.self)?
                    .element.as(IdentifierTypeSyntax.self)?.name.text {
                    return element
                }
                let polarity: String
                switch property {
                case "preservationClaims":
                    polarity = "Preservation"
                case "detectionClaims":
                    polarity = "Detection"
                default:
                    return nil
                }
                return codeTokens(type) == ["DeclaredClaims", "<", polarity, ">"] ? "Claim" : nil
            }
        }
        return nil
    }

    private static func storedPropertyType(in source: String, owner: String, property: String) -> String? {
        let tree = Parser.parse(source: source)
        let matches = tree.statements.compactMap { $0.item.as(StructDeclSyntax.self) }
            .filter { $0.name.text == owner }
        guard matches.count == 1, let declaration = matches.first else {
            return nil
        }
        for member in declaration.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else {
                continue
            }
            for binding in variable.bindings where
                binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == property {
                guard let type = binding.typeAnnotation?.type else {
                    return nil
                }
                if let identifier = type.as(IdentifierTypeSyntax.self), identifier.genericArgumentClause == nil {
                    return identifier.name.text
                }
                if let element = type.as(ArrayTypeSyntax.self)?.element.as(IdentifierTypeSyntax.self),
                    element.genericArgumentClause == nil {
                    return "[" + element.name.text + "]"
                }
                return nil
            }
        }
        return nil
    }

    static func worldSpaceAxisViolations(worldSource: String, worldSpaceSource: String) -> [LawViolation] {
        guard let fields = storedProperties(in: worldSource, named: "WorldDefinition"),
            fields.contains("id"),
            let selections = worldSpaceSelectionTypes(in: worldSpaceSource),
            let axisPlan = structMethodBody(in: worldSpaceSource, owner: "WorldSpace", named: "axisPlan") else {
            return [violation(.catalogSerialization, file: worldSpacePath, subject: "world-space-axis-shape")]
        }
        var expected: [String: String] = [:]
        for field in fields where field != "id" {
            guard let type = storedPropertyType(in: worldSource, owner: "WorldDefinition", property: field) else {
                return [violation(.catalogSerialization, file: catalogWorldPath, subject: "world-space-axis-type")]
            }
            expected[kebabCase(field)] = type
        }
        guard Set(selections.values) == Set(expected.values).union(["MutantSelection"]),
            selections.count == expected.count + 1 else {
            return [violation(.catalogSerialization, file: worldSpacePath, subject: "world-space-axis-domain")]
        }
        var calls: [(name: String, type: String, selection: String)] = []
        var malformed = false
        func collect(_ node: Syntax) {
            if let call = node.as(FunctionCallExprSyntax.self),
                let method = call.calledExpression.as(MemberAccessExprSyntax.self),
                let base = method.base,
                codeTokens(base) == ["encoder"],
                ["appendAxis", "appendRawAxis"].contains(method.declName.baseName.text) {
                guard call.arguments.count == 2,
                    let name = call.arguments.first?.expression,
                    let label = simpleStringLiteral(name),
                    let selection = call.arguments.last?.expression,
                    let selected = codeTokens(selection).first,
                    codeTokens(selection) == [selected],
                    let type = selections[selected] else {
                    malformed = true
                    return
                }
                calls.append((label, type, selected))
            }
            for child in node.children(viewMode: .sourceAccurate) {
                collect(child)
            }
        }
        collect(Syntax(axisPlan))
        let statements = Array(axisPlan.statements)
        guard statements.count == expected.count + 3,
            codeTokens(statements[0].item) == ["var", "encoder", "=", "try", "WorldDefinitionEncoder", "(", ")"],
            codeTokens(statements[expected.count + 1].item) == [
                "let", "mutantCount", "=", "try", "encoder", ".", "appendMutants", "(", "mutants", ")",
            ],
            codeTokens(statements[expected.count + 2].item) == [
                "return", "try", "encoder", ".", "plan", "(",
                "mutantCount", ":", "mutantCount", ")",
            ] else {
            return [violation(.catalogSerialization, file: worldSpacePath, subject: "world-space-axis-shape")]
        }
        let directCalls = statements.dropFirst().prefix(expected.count).compactMap { statement -> FunctionCallExprSyntax? in
            let expression: ExprSyntax
            if let wrapped = statement.item.as(ExpressionStmtSyntax.self)?.expression {
                expression = wrapped
            } else if let direct = statement.item.as(ExprSyntax.self) {
                expression = direct
            } else {
                return nil
            }
            let unwrapped: ExprSyntax
            if let tried = expression.as(TryExprSyntax.self) {
                unwrapped = tried.expression
            } else {
                unwrapped = expression
            }
            guard let call = unwrapped.as(FunctionCallExprSyntax.self),
                let method = call.calledExpression.as(MemberAccessExprSyntax.self),
                let base = method.base,
                codeTokens(base) == ["encoder"],
                ["appendAxis", "appendRawAxis"].contains(method.declName.baseName.text) else {
                return nil
            }
            return call
        }
        if malformed || calls.count != expected.count || directCalls.count != calls.count {
            return [violation(.catalogSerialization, file: worldSpacePath, subject: "world-space-axis-shape")]
        }
        var seen = Set<String>()
        var violations: [LawViolation] = []
        for call in calls {
            if !seen.insert(call.name).inserted || expected[call.name] != call.type {
                violations.append(violation(
                    .catalogSerialization,
                    file: worldSpacePath,
                    subject: "world-space-axis-binding:" + call.name
                ))
            }
        }
        for missing in Set(expected.keys).subtracting(seen).sorted() {
            violations.append(violation(
                .catalogSerialization,
                file: worldSpacePath,
                subject: "world-space-axis-missing:" + missing
            ))
        }
        if violations.isEmpty && !worldIteratorAxesAreDirectlyBound(
            worldSpaceSource: worldSpaceSource,
            fields: fields,
            calls: calls
        ) {
            violations.append(violation(
                .catalogSerialization,
                file: worldSpacePath,
                subject: "world-iterator-axis"
            ))
        }
        if violations.isEmpty && !worldSpacePlanIsShared(worldSpaceSource: worldSpaceSource) {
            violations.append(violation(
                .catalogSerialization,
                file: worldSpacePath,
                subject: "world-space-plan-sharing"
            ))
        }
        if violations.isEmpty && !worldSpacePlanHandoffIsDirect(worldSpaceSource: worldSpaceSource) {
            violations.append(violation(
                .catalogSerialization,
                file: worldSpacePath,
                subject: "world-space-plan-handoff"
            ))
        }
        if violations.isEmpty && !worldSpaceCursorKernelIsDirect(worldSpaceSource: worldSpaceSource) {
            violations.append(violation(
                .catalogSerialization,
                file: worldSpacePath,
                subject: "world-space-cursor-kernel"
            ))
        }
        return violations
    }

    private static func worldSpacePlanIsShared(worldSpaceSource: String) -> Bool {
        guard let count = structMethodBody(in: worldSpaceSource, owner: "WorldSpace", named: "executionCount"),
            let worlds = structMethodBody(in: worldSpaceSource, owner: "WorldSpace", named: "allWorlds"),
            count.statements.count == 1,
            count.statements.first.map({ codeTokens($0.item) }) == ["try", "axisPlan", "(", ")", ".", "count"],
            worlds.statements.count == 2,
            worlds.statements.first.map({ codeTokens($0.item) }) == ["let", "plan", "=", "try", "axisPlan", "(", ")"] else {
            return false
        }
        let returned = codeTokens(Array(worlds.statements)[1].item)
        return returned == ["return", "WorldSequence", "(", "space", ":", "self", ",", "plan", ":", "plan", ")"]
    }

    private static func worldSpacePlanHandoffIsDirect(worldSpaceSource: String) -> Bool {
        guard storedPropertyType(in: worldSpaceSource, owner: "WorldSequence", property: "plan") == "WorldAxisPlan",
            storedPropertyType(in: worldSpaceSource, owner: "WorldIterator", property: "plan") == "WorldAxisPlan",
            structPropertyTokens(in: worldSpaceSource, owner: "WorldSequence", named: "plan") == [
                "private", "let", "plan", ":", "WorldAxisPlan",
            ],
            structPropertyTokens(in: worldSpaceSource, owner: "WorldIterator", named: "plan") == [
                "private", "let", "plan", ":", "WorldAxisPlan",
            ],
            let sequenceCount = structPropertyTokens(in: worldSpaceSource, owner: "WorldSequence", named: "count"),
            let sequenceInit = structInitializerBody(in: worldSpaceSource, owner: "WorldSequence"),
            let iteratorInit = structInitializerBody(in: worldSpaceSource, owner: "WorldIterator"),
            let makeIterator = structMethodBody(in: worldSpaceSource, owner: "WorldSequence", named: "makeIterator") else {
            return false
        }
        return sequenceCount == ["public", "var", "count", ":", "Int", "{", "plan", ".", "count", ".", "rawValue", "}"]
            && Array(sequenceInit.statements).map({ codeTokens($0.item) }) == [
            ["self", ".", "space", "=", "space"],
            ["self", ".", "plan", "=", "plan"],
        ] && Array(iteratorInit.statements).map({ codeTokens($0.item) }) == [
            ["self", ".", "space", "=", "space"],
            ["self", ".", "plan", "=", "plan"],
            ["self", ".", "position", "=", "0"],
        ] && Array(makeIterator.statements).map({ codeTokens($0.item) }) == [
            ["WorldIterator", "(", "space", ":", "space", ",", "plan", ":", "plan", ")"],
        ]
    }

    private static func worldSpaceCursorKernelIsDirect(worldSpaceSource: String) -> Bool {
        guard let initialized = structInitializerBody(in: worldSpaceSource, owner: "CartesianCursor"),
            let take = structMethodBody(in: worldSpaceSource, owner: "CartesianCursor", named: "take"),
            let skip = structMethodBody(in: worldSpaceSource, owner: "WorldIterator", named: "skip"),
            let next = structMethodBody(in: worldSpaceSource, owner: "WorldIterator", named: "next") else {
            return false
        }
        let initialization = Array(initialized.statements).map { codeTokens($0.item) }
        let digit = Array(take.statements).map { codeTokens($0.item) }
        let skipped = Array(skip.statements).map { codeTokens($0.item) }
        let nextStatements = Array(next.statements)
        let iteration = nextStatements.map { codeTokens($0.item) }
        guard nextStatements.count == 5,
            let worldBinding = nextStatements[2].item.as(VariableDeclSyntax.self),
            worldBinding.bindingSpecifier.text == "let",
            worldBinding.bindings.count == 1,
            let binding = worldBinding.bindings.first,
            binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "world",
            let constructor = binding.initializer?.value.as(FunctionCallExprSyntax.self),
            codeTokens(constructor.calledExpression) == ["World"] else {
            return false
        }
        return initialization == [
            ["self", ".", "ordinal", "=", "ordinal"],
            ["self", ".", "stride", "=", "total"],
        ] && digit == [
            ["let", "values", "=", "selection", ".", "executionValues"],
            ["stride", "/=", "values", ".", "count"],
            ["return", "values", "[", "(", "ordinal", "/", "stride", ")", "%", "values", ".", "count", "]"],
        ] && skipped == [
            ["let", "remaining", "=", "plan", ".", "count", ".", "rawValue", "-", "position"],
            ["if", "distance", ".", "rawValue", ">=", "remaining", "{",
             "position", "=", "plan", ".", "count", ".", "rawValue", "}", "else", "{",
             "position", "+=", "distance", ".", "rawValue", "}"],
        ] && iteration[0] == [
            "if", "position", "==", "plan", ".", "count", ".", "rawValue", "{", "return", "nil", "}",
        ]
            && iteration[1] == [
                "var", "cursor", "=", "CartesianCursor", "(",
                "total", ":", "plan", ".", "count", ".", "rawValue", ",",
                "ordinal", ":", "position", ")",
            ]
            && iteration[3] == ["position", "+=", "1"]
            && iteration[4] == ["return", "world"]
    }

    private static func worldIteratorAxesAreDirectlyBound(
        worldSpaceSource: String,
        fields: Set<String>,
        calls: [(name: String, type: String, selection: String)]
    ) -> Bool {
        guard let body = structMethodBody(in: worldSpaceSource, owner: "WorldIterator", named: "next") else {
            return false
        }
        var constructors: [FunctionCallExprSyntax] = []
        func collect(_ node: Syntax) {
            if let call = node.as(FunctionCallExprSyntax.self), codeTokens(call.calledExpression) == ["World"] {
                constructors.append(call)
            }
            for child in node.children(viewMode: .sourceAccurate) {
                collect(child)
            }
        }
        collect(Syntax(body))
        guard constructors.count == 1, let constructor = constructors.first,
            constructor.arguments.count == fields.count + 1 else {
            return false
        }
        var arguments: [String: ExprSyntax] = [:]
        for argument in constructor.arguments {
            guard let label = argument.label?.text,
                arguments.updateValue(argument.expression, forKey: label) == nil else {
                return false
            }
        }
        guard Set(arguments.keys) == fields.union(["mutant"]),
            let id = arguments["id"],
            codeTokens(id) == [
                "WorldID", ".", "baseWorld", "(",
                "definition", ":", "plan", ".", "definition", ",",
                "ordinal", ":", "UInt", "(", "position", "/", "plan", ".", "mutantCount", ")", ")",
            ] else {
            return false
        }
        for call in calls {
            let labels = fields.filter { kebabCase($0) == call.name }
            guard labels.count == 1, let label = labels.first,
                let expression = arguments[label],
                codeTokens(expression) == [
                    "cursor", ".", "take", "(", "space", ".", call.selection, ")",
                ] else {
                return false
            }
        }
        guard let mutant = arguments["mutant"],
            codeTokens(mutant) == [
                "cursor", ".", "take", "(", "space", ".", "mutants", ")",
            ] else {
            return false
        }
        let selections = constructor.arguments.dropFirst().compactMap { argument -> String? in
            let tokens = codeTokens(argument.expression)
            guard tokens.count == 8,
                tokens[0...4].elementsEqual(["cursor", ".", "take", "(", "space"]),
                tokens[5] == ".", tokens[6] != "", tokens[7] == ")" else {
                return nil
            }
            return tokens[6]
        }
        return selections == calls.map(\.selection) + ["mutants"]
    }

    private static func worldSpaceSelectionTypes(in source: String) -> [String: String]? {
        let tree = Parser.parse(source: source)
        let matches = tree.statements.compactMap { $0.item.as(StructDeclSyntax.self) }
            .filter { $0.name.text == "WorldSpace" }
        guard matches.count == 1, let declaration = matches.first else {
            return nil
        }
        var selections: [String: String] = [:]
        for member in declaration.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else {
                continue
            }
            for binding in variable.bindings {
                guard let property = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                    let selection = binding.typeAnnotation?.type.as(IdentifierTypeSyntax.self),
                    selection.name.text == "AxisSelection",
                    let arguments = selection.genericArgumentClause?.arguments,
                    arguments.count == 1,
                    let value = arguments.first?.argument.as(IdentifierTypeSyntax.self),
                    value.genericArgumentClause == nil,
                    selections.updateValue(value.name.text, forKey: property) == nil else {
                    return nil
                }
            }
        }
        return selections.isEmpty ? nil : selections
    }

    private static func structMethodBody(in source: String, owner name: String, named method: String) -> CodeBlockSyntax? {
        guard let declaration = structDeclaration(in: source, named: name) else {
            return nil
        }
        let methods = declaration.memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }
            .filter { $0.name.text == method }
        return methods.count == 1 ? methods.first?.body : nil
    }

    private static func structInitializerBody(in source: String, owner name: String) -> CodeBlockSyntax? {
        guard let declaration = structDeclaration(in: source, named: name) else {
            return nil
        }
        let initializers = declaration.memberBlock.members.compactMap { $0.decl.as(InitializerDeclSyntax.self) }
        return initializers.count == 1 ? initializers.first?.body : nil
    }

    private static func structPropertyTokens(in source: String, owner name: String, named property: String) -> [String]? {
        guard let declaration = structDeclaration(in: source, named: name) else {
            return nil
        }
        let matches = declaration.memberBlock.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }
            .filter { variable in
                variable.bindings.count == 1
                    && variable.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == property
            }
        return matches.count == 1 ? matches.first.map { codeTokens($0) } : nil
    }

    private static func structDeclaration(in source: String, named name: String) -> StructDeclSyntax? {
        let tree = Parser.parse(source: source)
        let matches = tree.statements.compactMap { $0.item.as(StructDeclSyntax.self) }
            .filter { $0.name.text == name }
        return matches.count == 1 ? matches.first : nil
    }

    private static func kebabCase(_ value: String) -> String {
        var result = ""
        for character in value {
            if character.isUppercase {
                result.append("-")
                result.append(contentsOf: character.lowercased())
            } else {
                result.append(character)
            }
        }
        return result
    }

    private static func serializedCatalogFields(in source: String) -> [SerializedCatalogField]? {
        let tree = Parser.parse(source: source)
        let matchingEnums = tree.statements.compactMap { $0.item.as(EnumDeclSyntax.self) }
            .filter { $0.name.text == "ReportCodec" }
        guard matchingEnums.count == 1, let owner = matchingEnums.first else {
            return nil
        }
        let matches = owner.memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }
            .filter { $0.name.text == "catalogValue" }
        guard matches.count == 1, let function = matches.first,
            function.signature.parameterClause.parameters.count == 1,
            let parameter = function.signature.parameterClause.parameters.first,
            parameter.secondName?.text == "catalog",
            parameter.type.as(IdentifierTypeSyntax.self)?.name.text == "EvidenceCatalog",
            let body = function.body else {
            return nil
        }
        var returns: [ReturnStmtSyntax] = []
        collectReturns(in: Syntax(body), into: &returns)
        guard returns.count == 1,
            let expression = returns.first?.expression else {
            return nil
        }
        return serializedObjectFields(in: expression)
    }

    private static func serializedObjectFields(in expression: ExprSyntax) -> [SerializedCatalogField]? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
            codeTokens(call.calledExpression) == [".", "object"],
            call.arguments.count == 1,
            let argument = call.arguments.first,
            let dictionary = argument.expression.as(DictionaryExprSyntax.self) else {
            return nil
        }
        if case .colon = dictionary.content {
            return []
        }
        guard case .elements(let elements) = dictionary.content else {
            return nil
        }
        var fields: [SerializedCatalogField] = []
        for element in elements {
            guard let literal = element.key.as(StringLiteralExprSyntax.self),
                literal.openingPounds == nil,
                literal.openingQuote.text == "\"",
                literal.closingQuote.text == "\"",
                literal.segments.count == 1,
                let segment = literal.segments.first?.as(StringSegmentSyntax.self) else {
                return nil
            }
            fields.append(SerializedCatalogField(
                name: segment.content.text,
                dependencies: catalogDependencies(in: Syntax(element.value)),
                value: element.value,
                nested: serializedObjectFields(in: element.value),
                offset: element.positionAfterSkippingLeadingTrivia.utf8Offset
            ))
        }
        return fields
    }

    private static func mappedObjectFields(
        in expression: ExprSyntax,
        property: String,
        elementType: String
    ) -> (fields: [SerializedCatalogField], elementName: String)? {
        let mapPath = elementType == "Claim"
            ? ["catalog", ".", property, ".", "definitions", ".", "map"]
            : ["catalog", ".", property, ".", "map"]
        guard let arrayCall = expression.as(FunctionCallExprSyntax.self),
            codeTokens(arrayCall.calledExpression) == [".", "array"],
            arrayCall.arguments.count == 1,
            let argument = arrayCall.arguments.first,
            let mapCall = argument.expression.as(FunctionCallExprSyntax.self),
            codeTokens(mapCall.calledExpression) == mapPath,
            mapCall.arguments.isEmpty,
            let closure = mapCall.trailingClosure,
            closure.statements.count == 1,
            let statement = closure.statements.first,
            let object = statement.item.as(FunctionCallExprSyntax.self),
            let fields = serializedObjectFields(in: ExprSyntax(object)) else {
            return nil
        }
        let elementName: String
        if let signature = closure.signature {
            guard let clause = signature.parameterClause,
                clause.as(ClosureShorthandParameterListSyntax.self)?.count == 1,
                let parameter = clause.as(ClosureShorthandParameterListSyntax.self)?.first else {
                return nil
            }
            elementName = parameter.name.text
        } else {
            elementName = "$0"
        }
        return (fields, elementName)
    }

    private static func collectReturns(in node: Syntax, into returns: inout [ReturnStmtSyntax]) {
        if let statement = node.as(ReturnStmtSyntax.self) {
            returns.append(statement)
        }
        for child in node.children(viewMode: .sourceAccurate) {
            collectReturns(in: child, into: &returns)
        }
    }

    private static func catalogDependencies(in node: Syntax) -> Set<String> {
        var fields = Set<String>()
        if let access = node.as(MemberAccessExprSyntax.self),
            let base = access.base?.as(DeclReferenceExprSyntax.self),
            base.baseName.text == "catalog" {
            fields.insert(access.declName.baseName.text)
        }
        for child in node.children(viewMode: .sourceAccurate) {
            fields.formUnion(catalogDependencies(in: child))
        }
        return fields
    }

    private static func memberPaths(
        in node: Syntax,
        rootedAt root: String,
        depth: Int
    ) -> Set<String> {
        var paths = Set<String>()
        if let access = node.as(MemberAccessExprSyntax.self),
            let path = memberPath(access, rootedAt: root), path.count == depth {
            paths.insert(path.joined(separator: "."))
        }
        for child in node.children(viewMode: .sourceAccurate) {
            paths.formUnion(memberPaths(in: child, rootedAt: root, depth: depth))
        }
        return paths
    }

    private static func memberPath(
        _ access: MemberAccessExprSyntax,
        rootedAt root: String
    ) -> [String]? {
        if let base = access.base?.as(DeclReferenceExprSyntax.self),
            base.baseName.text == root {
            return [access.declName.baseName.text]
        }
        if let base = access.base?.as(MemberAccessExprSyntax.self),
            let prefix = memberPath(base, rootedAt: root) {
            return prefix + [access.declName.baseName.text]
        }
        return nil
    }

    private static func eventGenerationViolations(in source: String) -> [LawViolation] {
        let tree = Parser.parse(source: source)
        var observers: [FunctionDeclSyntax] = []
        var persistors: [FunctionDeclSyntax] = []
        var advances: [FunctionDeclSyntax] = []
        var healthAdvances: [FunctionDeclSyntax] = []
        var healthInclusions: [FunctionDeclSyntax] = []
        var eventFreeRequirements: [FunctionDeclSyntax] = []
        var completions: [FunctionDeclSyntax] = []
        collectFunctions(named: "observeUnchanged", in: Syntax(tree), into: &observers)
        collectFunctions(named: "recordAttributeEvent", in: Syntax(tree), into: &persistors)
        collectFunctions(named: "recordingAttributeEvent", in: Syntax(tree), into: &advances)
        collectFunctions(named: "advanceForAttribute", in: Syntax(tree), into: &healthAdvances)
        collectFunctions(named: "including", in: Syntax(tree), into: &healthInclusions)
        collectFunctions(named: "requireEventFree", in: Syntax(tree), into: &eventFreeRequirements)
        collectFunctions(named: "complete", in: Syntax(tree), into: &completions)
        let healthInclusionsOwned = healthInclusions.filter {
            containingStructName($0) == "FileEventHealth"
        }
        let healthRequirements = eventFreeRequirements.filter {
            containingStructName($0) == "FileEventHealth"
        }
        let leaseRequirements = eventFreeRequirements.filter {
            containingStructName($0) == "FileEventLease"
        }
        guard observers.count == 1, persistors.count == 1, advances.count == 1,
            completions.count == 1, healthAdvances.count == 1,
            healthInclusionsOwned.count == 1,
            healthRequirements.count == 1, leaseRequirements.count == 1,
            let observer = observers.first, containingStructName(observer) == "FileEventLease",
            let persistor = persistors.first, containingClassName(persistor) == "HealthCell",
            let advance = advances.first, containingStructName(advance) == "FileEventWitness",
            let healthAdvance = healthAdvances.first,
            containingStructName(healthAdvance) == "FileEventHealth",
            let healthIncluding = healthInclusionsOwned.first,
            let healthRequirement = healthRequirements.first,
            let leaseRequirement = leaseRequirements.first,
            let completion = completions.first, containingClassName(completion) == "HealthCell",
            let observerBody = observer.body,
            let persistorBody = persistor.body,
            let advanceBody = advance.body,
            let healthAdvanceBody = healthAdvance.body,
            let healthIncludingBody = healthIncluding.body,
            let healthRequirementBody = healthRequirement.body,
            let leaseRequirementBody = leaseRequirement.body,
            let completionBody = completion.body else {
            return [violation(
                .eventGenerationWitness,
                file: eventLeasePath,
                subject: "witness-shape"
            )]
        }
        let attributeBranch = [
            "if", "case", ".", "attributeAmbiguous", "(", "let", "path", ")", "=", "event", ",",
            "let", "error", "=", "health", ".", "recordAttributeEvent", "(",
            "at", ":", "path", ")",
            "{", "throw", "error", "}",
        ]
        let persistsGuard = [
            "guard", "let", "next", "=", "prior", ".", "advanceForAttribute", "(",
            "at", ":", "path", ")",
            "else", "{", "let", "error", "=", "PlatformError", ".", "eventGenerationOverflow",
            "state", "=", ".", "invalid", "(", "error", ")", "return", "error", "}",
        ]
        let advanceGuard = [
            "guard", "let", "next", "=", "generation", ".", "advanced", "(", ")",
            "else", "{", "return", "nil", "}",
        ]
        let observerStatements = Array(observerBody.statements)
        guard observerStatements.count == 4,
            observerStatements[0].item.as(ExpressionStmtSyntax.self)?
                .expression.as(SwitchExprSyntax.self) != nil,
            observerStatements[1].item.as(VariableDeclSyntax.self) != nil,
            observerStatements[2].item.as(DoStmtSyntax.self) != nil,
            let loop = observerStatements[3].item.as(WhileStmtSyntax.self),
            codeTokens(loop.conditions) == ["true"] else {
            return [violation(
                .eventGenerationWitness,
                file: eventLeasePath,
                subject: "observer-order"
            )]
        }
        let loopStatements = Array(loop.body.statements)
        guard loopStatements.count == 3,
            loopStatements[0].item.as(VariableDeclSyntax.self) != nil,
            codeTokens(loopStatements[0]) == [
                "let", "event", "=", "queue", ".", "nextEvent", "(", ")",
            ],
            let attribute = loopStatements[1].item.as(ExpressionStmtSyntax.self)?
                .expression.as(IfExprSyntax.self),
            codeTokens(attribute) == attributeBranch,
            let transitionSwitch = loopStatements[2].item.as(ExpressionStmtSyntax.self)?
                .expression.as(SwitchExprSyntax.self),
            codeTokens(transitionSwitch.subject) == [
                "transition", ".", "observing", "(", "Self", ".",
                "observation", "(", "for", ":", "event", ")", ")",
            ] else {
            return [violation(
                .eventGenerationWitness,
                file: eventLeasePath,
                subject: "observer-order"
            )]
        }
        guard transitionSwitch.cases.count == 3,
            let verified = switchCase(
                labeled: ["case", ".", "verified", "(", "let", "continuity", ")", ":"],
                in: transitionSwitch
            ),
            let verifiedStatements = directStatements(in: verified, count: 1),
            let healthSwitch = verifiedStatements[0].item.as(ExpressionStmtSyntax.self)?
                .expression.as(SwitchExprSyntax.self),
            codeTokens(healthSwitch.subject) == [
                "health", ".", "complete", "(", "continuity", ")",
            ],
            healthSwitch.cases.count == 2,
            let activeWitness = switchCase(
                labeled: ["case", ".", "active", "(", "let", "active", ")", ":"],
                in: healthSwitch
            ),
            let activeWitnessStatements = directStatements(in: activeWitness, count: 1),
            codeTokens(activeWitnessStatements[0]) == ["return", "active", ".", "witness"],
            let invalidWitness = switchCase(
                labeled: ["case", ".", "invalid", "(", "let", "error", ")", ":"],
                in: healthSwitch
            ),
            let invalidWitnessStatements = directStatements(in: invalidWitness, count: 1),
            codeTokens(invalidWitnessStatements[0]) == ["throw", "error"] else {
            return [violation(
                .eventGenerationWitness,
                file: eventLeasePath,
                subject: "verified-retention"
            )]
        }
        let persistorStatements = Array(persistorBody.statements)
        guard persistorStatements.count == 3,
            let persistenceSwitch = persistorStatements[2].item.as(ExpressionStmtSyntax.self)?
                .expression.as(SwitchExprSyntax.self),
            codeTokens(persistenceSwitch.subject) == ["state"],
            persistenceSwitch.cases.count == 2,
            let activePersistence = switchCase(
                labeled: ["case", ".", "active", "(", "let", "prior", ")", ":"],
                in: persistenceSwitch
            ),
            let activeStatements = directStatements(in: activePersistence, count: 3),
            activeStatements[0].item.as(GuardStmtSyntax.self) != nil,
            codeTokens(activeStatements[0]) == persistsGuard,
            codeTokens(activeStatements[1]) == ["state", "=", ".", "active", "(", "next", ")"],
            codeTokens(activeStatements[2]) == ["return", "nil"] else {
            return [violation(
                .eventGenerationWitness,
                file: eventLeasePath,
                subject: "witness-persistence"
            )]
        }
        let advanceStatements = Array(advanceBody.statements)
        guard advanceStatements.count == 2,
            advanceStatements[0].item.as(GuardStmtSyntax.self) != nil,
            codeTokens(advanceStatements[0]) == advanceGuard,
            codeTokens(advanceStatements[1]) == [
                "return", "FileEventWitness", "(", "continuity", ":", ".", "attributeAmbiguous",
                ",", "generation", ":", "next", ")",
            ] else {
            return [violation(
                .eventGenerationWitness,
                file: eventLeasePath,
                subject: "generation-advance"
            )]
        }
        let healthAdvanceStatements = Array(healthAdvanceBody.statements)
        guard healthAdvanceStatements.count == 4,
            codeTokens(healthAdvanceStatements[0]) == [
                "guard", "let", "next", "=", "witness", ".", "recordingAttributeEvent", "(", ")",
                "else", "{", "return", "nil", "}",
            ],
            codeTokens(healthAdvanceStatements[1]) == ["let", "first", ":", "WatchedPath"],
            healthAdvanceStatements[2].item.as(ExpressionStmtSyntax.self)?
                .expression.as(IfExprSyntax.self) != nil,
            codeTokens(healthAdvanceStatements[2]) == [
                "if", "let", "firstAttributePath", "{", "first", "=", "firstAttributePath", "}",
                "else", "{", "first", "=", "path", "}",
            ],
            codeTokens(healthAdvanceStatements[3]) == [
                "return", "FileEventHealth", "(", "witness", ":", "next", ",",
                "firstAttributePath", ":", "first", ")",
            ] else {
            return [violation(
                .eventGenerationWitness,
                file: eventLeasePath,
                subject: "path-retention"
            )]
        }
        let healthIncludingStatements = Array(healthIncludingBody.statements)
        guard healthIncludingStatements.count == 1,
            codeTokens(healthIncludingStatements[0]) == [
                "FileEventHealth", "(", "witness", ":", "witness", ".", "including", "(",
                "continuity", ")", ",", "firstAttributePath", ":", "firstAttributePath", ")",
            ] else {
            return [violation(
                .eventGenerationWitness,
                file: eventLeasePath,
                subject: "path-completion"
            )]
        }
        guard pathDiagnosticIsBound(
            healthRequirementBody: healthRequirementBody,
            leaseRequirementBody: leaseRequirementBody
        ) else {
            return [violation(
                .eventGenerationWitness,
                file: eventLeasePath,
                subject: "path-diagnostic"
            )]
        }
        let completionStatements = Array(completionBody.statements)
        guard completionStatements.count == 3,
            let completionSwitch = completionStatements[2].item.as(ExpressionStmtSyntax.self)?
                .expression.as(SwitchExprSyntax.self),
            codeTokens(completionSwitch.subject) == ["state"],
            completionSwitch.cases.count == 2,
            let activeCompletion = switchCase(
                labeled: ["case", ".", "active", "(", "let", "prior", ")", ":"],
                in: completionSwitch
            ),
            let completionActiveStatements = directStatements(in: activeCompletion, count: 2),
            codeTokens(completionActiveStatements[0]) == [
                "state", "=", ".", "active", "(", "prior", ".", "including", "(", "observed", ")", ")",
            ],
            codeTokens(completionActiveStatements[1]) == ["return", "state"] else {
            return [violation(
                .eventGenerationWitness,
                file: eventLeasePath,
                subject: "completion-preservation"
            )]
        }
        return []
    }

    private static func pathDiagnosticIsBound(
        healthRequirementBody: CodeBlockSyntax,
        leaseRequirementBody: CodeBlockSyntax
    ) -> Bool {
        let healthStatements = Array(healthRequirementBody.statements)
        guard healthStatements.count == 1,
            let healthSwitch = healthStatements[0].item.as(ExpressionStmtSyntax.self)?
                .expression.as(SwitchExprSyntax.self),
            codeTokens(healthSwitch.subject) == ["witness", ".", "continuity"],
            healthSwitch.cases.count == 2,
            let ambiguous = switchCase(
                labeled: ["case", ".", "attributeAmbiguous", ":"],
                in: healthSwitch
            ),
            let ambiguousStatements = directStatements(in: ambiguous, count: 2),
            codeTokens(ambiguousStatements[0]) == [
                "guard", "let", "firstAttributePath", "else", "{",
                "throw", ".", "attributeOriginMissing", "}",
            ],
            codeTokens(ambiguousStatements[1]) == [
                "throw", ".", "attributeAmbiguous", "(", "firstAttributePath", ")",
            ] else {
            return false
        }
        let leaseStatements = Array(leaseRequirementBody.statements)
        guard leaseStatements.count == 1,
            let leaseSwitch = leaseStatements[0].item.as(ExpressionStmtSyntax.self)?
                .expression.as(SwitchExprSyntax.self),
            codeTokens(leaseSwitch.subject) == [
                "try", "observeUnchanged", "(", ")", ".", "continuity",
            ],
            leaseSwitch.cases.count == 2,
            let leaseAmbiguous = switchCase(
                labeled: ["case", ".", "attributeAmbiguous", ":"],
                in: leaseSwitch
            ),
            let leaseAmbiguousStatements = directStatements(in: leaseAmbiguous, count: 1),
            let snapshotSwitch = leaseAmbiguousStatements[0].item.as(ExpressionStmtSyntax.self)?
                .expression.as(SwitchExprSyntax.self),
            codeTokens(snapshotSwitch.subject) == ["health", ".", "snapshot"],
            snapshotSwitch.cases.count == 2,
            let active = switchCase(
                labeled: ["case", ".", "active", "(", "let", "active", ")", ":"],
                in: snapshotSwitch
            ),
            let activeStatements = directStatements(in: active, count: 1),
            codeTokens(activeStatements[0]) == [
                "try", "active", ".", "requireEventFree", "(", ")",
            ] else {
            return false
        }
        return true
    }

    private static func switchCase(
        labeled label: [String],
        in expression: SwitchExprSyntax
    ) -> SwitchCaseSyntax? {
        let matches = expression.cases.compactMap { $0.as(SwitchCaseSyntax.self) }
            .filter { codeTokens($0.label) == label }
        return matches.count == 1 ? matches.first : nil
    }

    private static func directStatements(
        in branch: SwitchCaseSyntax,
        count: Int
    ) -> [CodeBlockItemSyntax]? {
        let statements = Array(branch.statements)
        return statements.count == count ? statements : nil
    }

    private static func eventPrepublicationViolations(in source: String) -> [LawViolation] {
        let tree = Parser.parse(source: source)
        var verifies: [FunctionDeclSyntax] = []
        collectFunctions(named: "verify", in: Syntax(tree), into: &verifies)
        guard verifies.count == 1,
            let verify = verifies.first,
            containingStructName(verify) == "SwiftestCommand",
            let body = verify.body else {
            return [violation(
                .eventGenerationWitness,
                file: commandPath,
                subject: "prepublication-shape"
            )]
        }
        let closureBindings = body.statements.compactMap { statement -> ClosureExprSyntax? in
            guard let variable = statement.item.as(VariableDeclSyntax.self),
                variable.bindings.count == 1,
                let binding = variable.bindings.first,
                binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "validateSource" else {
                return nil
            }
            return binding.initializer?.value.as(ClosureExprSyntax.self)
        }
        guard closureBindings.count == 1, let closure = closureBindings.first else {
            return [violation(
                .eventGenerationWitness,
                file: commandPath,
                subject: "prepublication-shape"
            )]
        }
        let closureTokens = codeTokens(closure)
        let verifyTokens = codeTokens(body)
        let finalWitness = [
            "let", "finalInput", "=", "InputEventWitness", "(",
            "source", ":", "try", "source", ".", "observeUnchanged", "(", ")", ",",
            "snapshot", ":", "try", "snapshot", ".", "observeUnchanged", "(", ")", ")",
        ]
        let comparesFullWitness = [
            "guard", "finalInput", "==", "reportInput", "else", "{",
            "throw", "CLIError", ".", "platform", "(", ".", "lateInputEvent", ")", "}",
        ]
        let closureStatements = Array(closure.statements)
        guard closureStatements.count == 4,
            closureStatements[1].item.as(VariableDeclSyntax.self) != nil,
            codeTokens(closureStatements[1]) == finalWitness,
            closureStatements[2].item.as(GuardStmtSyntax.self) != nil,
            codeTokens(closureStatements[2]) == comparesFullWitness,
            closureTokens.filter({ $0 == "finalInput" }).count == 2,
            verifyTokens.filter({ $0 == "validateSource" }).count == 3,
            containsCodeSequence([
                "try", "outputOwner", ".", "writeValidated", "(", "data", ",",
                "validating", ":", "validateSource", ")",
            ], in: verifyTokens),
            containsCodeSequence(["try", "validateSource", "(", ")"], in: verifyTokens) else {
            return [violation(
                .eventGenerationWitness,
                file: commandPath,
                subject: "prepublication-witness"
            )]
        }
        return []
    }

    private static func vnodeEventViolations(
        _ tokens: [TokenSyntax],
        source: String,
        path: String,
        boundaryPolicy: BoundaryPolicy,
        requirement: VnodeRegistrationRequirement
    ) -> [LawViolation] {
        let vnodeTokens = tokens.filter { token in
            token.text == "EVFILT_VNODE" && !isLiteralMaterial(token.tokenKind)
        }
        let registrationCalls = tokens.compactMap { token -> FunctionCallExprSyntax? in
            guard token.text == "kevent64_s", !isLiteralMaterial(token.tokenKind),
                let call = enclosingCall(for: token),
                call.arguments.contains(where: { $0.label?.text == "filter" }) else {
                return nil
            }
            return call
        }
        let rawQueueTokens = tokens.filter { token in
            ["kqueue", "kevent64", "kevent64_s"].contains(token.text)
                && !isLiteralMaterial(token.tokenKind)
        }
        let rawQueueCalls = rawQueueTokens.compactMap { token -> FunctionCallExprSyntax? in
            guard
                let call = enclosingCall(for: token),
                codeTokens(call.calledExpression).last == token.text else {
                return nil
            }
            return call
        }
        guard boundaryPolicy == .swiftestRepository && path == vnodeABIRelativePath else {
            return vnodeTokens.map { token in
                violation(
                    .vnodeEventProtocol,
                    file: path,
                    source: source,
                    offset: token.positionAfterSkippingLeadingTrivia.utf8Offset,
                    subject: "raw-vnode-filter"
                )
            } + rawQueueTokens.map { token in
                violation(
                    .vnodeEventProtocol,
                    file: path,
                    source: source,
                    offset: token.positionAfterSkippingLeadingTrivia.utf8Offset,
                    subject: "raw-event-queue"
                )
            }
        }
        if vnodeTokens.isEmpty && registrationCalls.isEmpty && requirement == .fragment {
            return []
        }
        guard vnodeTokens.count == 1, registrationCalls.count == 1,
            let vnodeToken = vnodeTokens.first,
            let call = registrationCalls.first,
            contains(call, token: vnodeToken),
            let owner = containingFunction(call),
            owner.name.text == "makeVnodeRegistration",
            owner.modifiers.contains(where: { $0.name.text == "private" }),
            owner.modifiers.contains(where: { $0.name.text == "static" }),
            containingEnumName(owner) == "ABIAdapter",
            let returnClause = owner.signature.returnClause,
            codeTokens(returnClause.type) == ["Darwin", ".", "kevent64_s"],
            codeTokens(call.calledExpression) == ["Darwin", ".", "kevent64_s"],
            let ident = call.arguments.first(where: { $0.label?.text == "ident" }),
            let filter = call.arguments.first(where: { $0.label?.text == "filter" }),
            let flags = call.arguments.first(where: { $0.label?.text == "flags" }),
            let filterFlags = call.arguments.first(where: { $0.label?.text == "fflags" }),
            codeTokens(ident.expression) == ["UInt64", "(", "descriptor", ")"],
            codeTokens(filter.expression) == ["Int16", "(", "EVFILT_VNODE", ")"],
            codeTokens(flags.expression) == [
                "UInt16", "(", "EV_ADD", "|", "EV_ENABLE", "|", "EV_CLEAR", ")",
            ],
            codeTokens(filterFlags.expression) == ["mutationFlags"] else {
            let offset: Int
            if let vnodeToken = vnodeTokens.first {
                offset = vnodeToken.positionAfterSkippingLeadingTrivia.utf8Offset
            } else if let call = registrationCalls.first {
                offset = call.positionAfterSkippingLeadingTrivia.utf8Offset
            } else {
                offset = 0
            }
            return [violation(
                .vnodeEventProtocol,
                file: path,
                source: source,
                offset: offset,
                subject: "registration-shape"
            )]
        }
        if requirement == .completeABI && !vnodeRegistrationPipelineValid(
            in: source,
            calls: rawQueueCalls,
            rawTokenCount: rawQueueTokens.count
        ) {
            return [violation(
                .vnodeEventProtocol,
                file: path,
                subject: "registration-path"
            )]
        }
        return []
    }

    private static func enclosingCall(for token: TokenSyntax) -> FunctionCallExprSyntax? {
        var node = Syntax(token)
        while let parent = node.parent {
            if let call = parent.as(FunctionCallExprSyntax.self) {
                return call
            }
            node = parent
        }
        return nil
    }

    private static func containingFunction(_ call: FunctionCallExprSyntax) -> FunctionDeclSyntax? {
        var node = Syntax(call)
        while let parent = node.parent {
            if let declaration = parent.as(FunctionDeclSyntax.self) {
                return declaration
            }
            node = parent
        }
        return nil
    }

    private static func containingEnumName(_ declaration: FunctionDeclSyntax) -> String? {
        var node = Syntax(declaration)
        while let parent = node.parent {
            if let owner = parent.as(EnumDeclSyntax.self) {
                return owner.name.text
            }
            node = parent
        }
        return nil
    }

    private static func contains(_ call: FunctionCallExprSyntax, token: TokenSyntax) -> Bool {
        let position = token.positionAfterSkippingLeadingTrivia.utf8Offset
        return call.positionAfterSkippingLeadingTrivia.utf8Offset <= position
            && position < call.endPositionBeforeTrailingTrivia.utf8Offset
    }

    private static func codeTokens(_ syntax: some SyntaxProtocol) -> [String] {
        syntax.tokens(viewMode: .sourceAccurate)
            .filter { !isLiteralMaterial($0.tokenKind) }
            .map(\.text)
    }

    private struct VnodeLocal {
        let index: Int
        let specifier: String
        let expression: ExprSyntax
    }

    private static func vnodeRegistrationPipelineValid(
        in source: String,
        calls: [FunctionCallExprSyntax],
        rawTokenCount: Int
    ) -> Bool {
        let queueCalls = calls.filter { codeTokens($0.calledExpression) == ["Darwin", ".", "kqueue"] }
        let eventConstructors = calls.filter {
            codeTokens($0.calledExpression) == ["Darwin", ".", "kevent64_s"]
        }
        let eventCalls = calls.filter { codeTokens($0.calledExpression) == ["Darwin", ".", "kevent64"] }
        guard calls.count == 5, rawTokenCount == calls.count + 1,
            queueCalls.count == 1, eventConstructors.count == 2,
            eventCalls.count == 2,
            let queueCall = queueCalls.first, queueCall.arguments.isEmpty,
            let receiveConstructor = eventConstructors.first(where: {
                $0.arguments.isEmpty && containingFunction($0)?.name.text == "nextEvent"
            }),
            containingStructName(receiveConstructor) == "VnodeEventQueue",
            let receiveCall = eventCalls.first(where: {
                containingFunction($0)?.name.text == "nextEvent"
            }),
            containingStructName(receiveCall) == "VnodeEventQueue",
            receiveCall.arguments.map({ codeTokens($0.expression) }) == [
                ["descriptor"], ["nil"], ["0"], ["&", "event"],
                ["1"], ["0"], ["&", "timeout"],
            ],
            let registrationCall = eventCalls.first(where: {
                containingFunction($0)?.name.text == "registerOnDarwin"
            }),
            containingStructName(registrationCall) == "VnodeEventQueue",
            registrationCall.arguments.map({ codeTokens($0.expression) }) == [
                ["descriptor"], ["change"], ["1"], ["nil"], ["0"], ["0"], ["nil"],
            ] else {
            return false
        }
        let tree = Parser.parse(source: source)
        var functions: [FunctionDeclSyntax] = []
        collectFunctions(named: "registerOnDarwin", in: Syntax(tree), into: &functions)
        guard functions.count == 1, let registration = functions.first,
            containingStructName(registration) == "VnodeEventQueue",
            registration.modifiers.contains(where: { $0.name.text == "private" }),
            registration.modifiers.contains(where: { $0.name.text == "mutating" }),
            let flags = vnodeLocal(named: "mutationFlags", in: registration),
            let event = vnodeLocal(named: "event", in: registration),
            let status = vnodeLocal(named: "status", in: registration),
            flags.specifier == "let", event.specifier == "var", status.specifier == "let",
            event.index == flags.index + 1, status.index == event.index + 1,
            codeTokens(flags.expression) == [
                "UInt32", "(", "NOTE_DELETE", "|", "NOTE_WRITE", "|", "NOTE_EXTEND", "|",
                "NOTE_LINK", "|", "NOTE_RENAME", "|", "NOTE_REVOKE", "|", "NOTE_ATTRIB", ")",
            ],
            codeTokens(event.expression) == [
                "ABIAdapter", ".", "makeVnodeRegistration", "(",
                "descriptor", ":", "watchedDescriptor", ",",
                "mutationFlags", ":", "mutationFlags", ")",
            ],
            codeTokens(status.expression) == [
                "withUnsafePointer", "(", "to", ":", "&", "event", ")",
                "{", "change", "in", "Darwin", ".", "kevent64", "(",
                "descriptor", ",", "change", ",", "1", ",", "nil", ",",
                "0", ",", "0", ",", "nil", ")", "}",
            ] else {
            return false
        }
        return true
    }

    private static func collectFunctions(
        named name: String,
        in node: Syntax,
        into functions: inout [FunctionDeclSyntax]
    ) {
        if let function = node.as(FunctionDeclSyntax.self), function.name.text == name {
            functions.append(function)
        }
        for child in node.children(viewMode: .sourceAccurate) {
            collectFunctions(named: name, in: child, into: &functions)
        }
    }

    private static func vnodeLocal(named name: String, in function: FunctionDeclSyntax) -> VnodeLocal? {
        guard let body = function.body else {
            return nil
        }
        for (index, item) in body.statements.enumerated() {
            guard let declaration = item.item.as(VariableDeclSyntax.self),
                declaration.bindings.count == 1,
                let binding = declaration.bindings.first,
                binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name,
                let initializer = binding.initializer else {
                continue
            }
            return VnodeLocal(
                index: index,
                specifier: declaration.bindingSpecifier.text,
                expression: initializer.value
            )
        }
        return nil
    }

    private static func containingStructName(_ node: some SyntaxProtocol) -> String? {
        var syntax = Syntax(node)
        while let parent = syntax.parent {
            if let owner = parent.as(StructDeclSyntax.self) {
                return owner.name.text
            }
            syntax = parent
        }
        return nil
    }

    private static func containingClassName(_ node: some SyntaxProtocol) -> String? {
        var syntax = Syntax(node)
        while let parent = syntax.parent {
            if let owner = parent.as(ClassDeclSyntax.self) {
                return owner.name.text
            }
            syntax = parent
        }
        return nil
    }

    private static func tokenViolations(
        _ tokens: [TokenRecord],
        source: String,
        path: String,
        boundaryPolicy: BoundaryPolicy
    ) -> [LawViolation] {
        var violations: [LawViolation] = []
        let selfPolicy = boundaryPolicy == .swiftestRepository
        let platformBoundary = selfPolicy && path.hasPrefix("Sources/SwiftestPlatform/")
        let abiBoundary = selfPolicy && path == "Sources/" + AuditedBoundary.platformABI.rawValue
        let testingBoundary = selfPolicy && path == "Sources/" + AuditedBoundary.testingStableABI.rawValue
        let pluginInputBoundary = selfPolicy && path == "Plugins/SwiftestLawsPlugin/PluginInputInventory.swift"
        let hasClosedDomain = containsSequence(["@", "ClosedDomain"], tokens: tokens)
        for index in tokens.indices {
            let token = tokens[index]
            let previous = index > 0 ? tokens[index - 1].text : ""
            let beforePrevious = index > 1 ? tokens[index - 2].text : ""
            let next = index + 1 < tokens.count ? tokens[index + 1].text : ""
            let nextTwo = index + 2 < tokens.count ? tokens[index + 2].text : ""
            if token.text == "try" && (next == "?" || next == "!") {
                violations.append(at(.prohibitedTry, token: token, source: source, path: path))
            }
            if token.text == "as" && next == "!" {
                violations.append(at(.forceCast, token: token, source: source, path: path))
            }
            if token.isForceUnwrap {
                violations.append(at(.forceUnwrap, token: token, source: source, path: path))
            }
            if token.text == "throw" && next.hasPrefix("\"") {
                violations.append(at(.stringError, token: token, source: source, path: path))
            }
            if token.text == "NSError" {
                violations.append(at(.stringError, token: token, source: source, path: path))
            }
            if token.text == "_" && next == "=" {
                violations.append(at(.ignoredResult, token: token, source: source, path: path))
            }
            if token.text == "??" {
                violations.append(at(.semanticDefault, token: token, source: source, path: path))
            }
            if token.text == "Bool" && (next == "?" || (previous == "<" && next == ">")) {
                violations.append(at(.optionalBoolean, token: token, source: source, path: path))
            }
            if token.text == ":" && next == "Bool" && isPolicyName(previous) {
                violations.append(at(.policyBoolean, token: token, source: source, path: path))
            }
            if hasClosedDomain && token.text == "default" && next == ":" {
                violations.append(at(.defaultClosedDomain, token: token, source: source, path: path))
            }
            if token.text == "static" && next == "let" && nextTwo == "allCases" {
                violations.append(at(.handwrittenCases, token: token, source: source, path: path))
            }
            if token.text == "Process" && !platformBoundary {
                violations.append(at(.rawProcess, token: token, source: source, path: path))
            }
            if token.text == "Task" && next == "." && nextTwo == "detached" && !platformBoundary {
                violations.append(at(.detachedTask, token: token, source: source, path: path))
            }
            if token.text == "var" && (token.isFileScope || token.isTypeStaticVar) {
                violations.append(at(.globalMutableState, token: token, source: source, path: path))
            }
            if token.text == "any" && !testingBoundary && !platformBoundary && previous != "isolated" {
                violations.append(at(.ownedExistential, token: token, source: source, path: path))
            }
            if token.text == "Any" {
                violations.append(at(.anyType, token: token, source: source, path: path))
            }
            if token.text == "Mirror" {
                violations.append(at(.mirror, token: token, source: source, path: path))
            }
            if token.text == "&+" || token.text == "&-" || token.text == "&*" {
                violations.append(at(.uncheckedArithmetic, token: token, source: source, path: path))
            }
            if token.text == "ProcessInfo" && !platformBoundary {
                violations.append(at(.directEnvironment, token: token, source: source, path: path))
            }
            if (token.text == "ContinuousClock" || (token.text == "Date" && nextTwo == "now"))
                && !platformBoundary {
                violations.append(at(.directClock, token: token, source: source, path: path))
            }
            if (token.text == "SystemRandomNumberGenerator"
                || token.text == "UUID"
                || (previous == "." && token.text == "random" && next == "(" && nextTwo == "in"))
                && !platformBoundary {
                violations.append(at(.directRandomness, token: token, source: source, path: path))
            }
            if ((token.text == "FileManager" && !pluginInputBoundary)
                || (token.text == "createDirectory"
                    && next == "("
                    && !(beforePrevious == "FileSystemBoundary" && previous == "."))
                || token.text == "removeItem"
                || token.text == "moveItem"
                || token.text == "copyItem"
                || token.text == "createFile"
                || token.text == "replaceItem"
                || token.text == "setAttributes"
                || (previous == "." && token.text == "write" && next == "(" && nextTwo == "to"))
                && !platformBoundary {
                violations.append(at(.directFileWrite, token: token, source: source, path: path))
            }
            if !abiBoundary && libcFilesystemSymbols.contains(token.text) {
                violations.append(at(.directFileWrite, token: token, source: source, path: path))
            }
            if !abiBoundary && (token.text == "open" || token.text == "link") && next == "("
                && previous != "func" && previous != "case" {
                violations.append(at(.directFileWrite, token: token, source: source, path: path))
            }
            if !abiBoundary && token.text == "write" && next == "("
                && previous != "func" && previous != "case"
                && (previous != "." || beforePrevious == "Darwin" || beforePrevious == "Foundation") {
                violations.append(at(.directFileWrite, token: token, source: source, path: path))
            }
            if !abiBoundary && token.text == "remove" && next == "("
                && previous != "func" && previous != "case"
                && (previous != "." || beforePrevious == "Darwin" || beforePrevious == "Foundation") {
                violations.append(at(.directFileWrite, token: token, source: source, path: path))
            }
            if !abiBoundary && libcProcessSymbols.contains(token.text) {
                violations.append(at(.rawProcess, token: token, source: source, path: path))
            }
            if (token.text.hasPrefix("withUnsafe")
                || token.text.hasPrefix("UnsafePointer")
                || token.text == "unsafeBitCast"
                || token.text == "_silgen_name"
                || (token.text == "unchecked" && previous == "@"))
                && !abiBoundary {
                violations.append(at(.unsafeOutsideBoundary, token: token, source: source, path: path))
            }
        }
        return violations
    }

    private static func macroViolations(
        _ tokens: [TokenSyntax],
        path: String,
        boundaryPolicy: BoundaryPolicy
    ) -> [LawViolation] {
        let allowed: [String: [(module: String, type: String)]] = [
            "WorldTest": [("SwiftestMacros", "WorldTestMacro")],
            "WorldUITest": [("SwiftestMacros", "WorldUITestMacro")],
            "Property": [("SwiftestMacros", "PropertyMacro")],
            "StateMachineTest": [("SwiftestMacros", "StateMachineTestMacro")],
            "PerformanceClaim": [("SwiftestMacros", "PerformanceClaimMacro")],
            "TestDouble": [("SwiftestMacros", "TestDoubleMacro")],
            "ClosedDomain": [("SwiftestMacros", "ClosedDomainMacro")],
            "eventually": [("SwiftestMacros", "EventuallyMacro")],
            "invariant": [("SwiftestMacros", "InvariantMacro")],
            "never": [("SwiftestMacros", "NeverMacro")],
        ]
        var violations: [LawViolation] = []
        for index in tokens.indices {
            guard tokens[index].text == "#",
                !isLiteralMaterial(tokens[index].tokenKind),
                index + 1 < tokens.count,
                tokens[index + 1].text == "externalMacro" else {
                continue
            }
            let arguments = Array(tokens.dropFirst(index + 2).prefix(12)).map(\.text)
            let module = macroArgument("module", in: arguments)
            let type = macroArgument("type", in: arguments)
            let declaration = containingMacroName(for: tokens[index])
            let inspected: Bool
            if let declaration, let implementations = allowed[declaration] {
                inspected = implementations.contains { module == $0.module && type == $0.type }
            } else {
                inspected = false
            }
            if boundaryPolicy != .swiftestRepository
                || path != "Sources/SwiftestTesting/Macros.swift" || !inspected {
                let subject: String
                if let declaration {
                    subject = declaration
                } else {
                    subject = "external-macro"
                }
                violations.append(violation(.uninspectedMacro, file: path, subject: subject))
            }
        }
        return violations
    }

    private static func containingMacroName(for token: TokenSyntax) -> String? {
        var node = Syntax(token)
        while let parent = node.parent {
            if let declaration = parent.as(MacroDeclSyntax.self) {
                return declaration.name.text
            }
            node = parent
        }
        return nil
    }

    private static func macroArgument(_ label: String, in tokens: [String]) -> String? {
        for index in tokens.indices where tokens[index] == label {
            if index + 4 < tokens.count,
                tokens[index + 1] == ":",
                tokens[index + 2] == "\"",
                tokens[index + 4] == "\"" {
                return tokens[index + 3]
            }
        }
        return nil
    }

    private static func validateExternalModuleGraph(
        manifest: ExternalPackageManifest,
        importsByPath: [String: Set<String>],
        root: String
    ) -> [LawViolation] {
        let targets = Dictionary(uniqueKeysWithValues: manifest.targets.map { ($0.name, $0) })
        var violations: [LawViolation] = []
        for target in manifest.targets {
            let parent = target.role == .test ? "Tests" : "Sources"
            let relative = parent + "/" + target.name
            do {
                if try FileSystemBoundary.entryKind(path: root + "/" + relative) != .directory {
                    violations.append(violation(.unclassifiedTarget, file: relative, subject: "not-directory"))
                }
            } catch {
                violations.append(violation(.unclassifiedTarget, file: relative, subject: "missing-target"))
            }
            if !importsByPath.keys.contains(where: { $0.hasPrefix(relative + "/") }) {
                violations.append(violation(.unclassifiedTarget, file: relative, subject: "missing-swift-source"))
            }
        }
        for parent in ["Sources", "Tests"] {
            let entries: [String]
            do {
                entries = try FileSystemBoundary.list(path: root + "/" + parent)
            } catch {
                if manifest.targets.contains(where: { ($0.role == .test ? "Tests" : "Sources") == parent }) {
                    violations.append(violation(.unreadableSource, file: parent, subject: "target-list"))
                }
                continue
            }
            for entry in entries {
                let relative = parent + "/" + entry
                guard let target = targets[entry],
                    (target.role == .test ? "Tests" : "Sources") == parent else {
                    violations.append(violation(.unclassifiedTarget, file: relative, subject: "undeclared-target"))
                    continue
                }
            }
        }
        let systemImports: Set<String> = [
            "Swift", "Foundation", "Dispatch", "Combine", "SwiftUI", "OSLog", "Testing", "XCTest",
        ]
        for relative in importsByPath.keys.sorted() {
            let components = relative.split(separator: "/").map(String.init)
            guard components.count >= 3,
                let target = targets[components[1]],
                (target.role == .test ? "Tests" : "Sources") == components[0],
                let imports = importsByPath[relative] else {
                violations.append(violation(.unclassifiedSource, file: relative, subject: "undeclared-source"))
                continue
            }
            for imported in imports.sorted() {
                if (imported == "Testing" || imported == "XCTest") && target.role != .test {
                    violations.append(violation(.testSupportImport, file: relative, subject: imported))
                } else if systemImports.contains(imported) {
                    continue
                } else if let dependency = targets[imported] {
                    if dependency.role == .test && target.role != .test {
                        violations.append(violation(.testSupportImport, file: relative, subject: imported))
                    } else if !target.dependencies.contains(imported) {
                        violations.append(violation(.reverseDependency, file: relative, subject: imported))
                    }
                } else {
                    violations.append(violation(.forbiddenDependency, file: relative, subject: imported))
                }
            }
        }
        return violations
    }

    private static func validateModuleGraph(
        importsByPath: [String: Set<String>],
        root: String
    ) -> [LawViolation] {
        let declarations = Dictionary(uniqueKeysWithValues: SwiftestModuleGraph.declarations.map { ($0.name, $0) })
        var violations: [LawViolation] = []
        let targetRoots = ["Sources", "Tests", "Plugins"]
        for targetRoot in targetRoots {
            let path = root + "/" + targetRoot
            let kind: FileEntryKind
            do {
                kind = try FileSystemBoundary.entryKind(path: path)
            } catch {
                continue
            }
            if kind != .directory {
                violations.append(violation(.unclassifiedTarget, file: targetRoot, subject: "not-directory"))
                continue
            }
            let entries: [String]
            do {
                entries = try FileSystemBoundary.list(path: path)
            } catch {
                violations.append(violation(.unreadableSource, file: targetRoot, subject: "list"))
                continue
            }
            for entry in entries {
                if declarations[entry] == nil {
                    violations.append(violation(
                        .unclassifiedTarget,
                        file: targetRoot + "/" + entry,
                        subject: entry
                    ))
                }
            }
        }
        for declaration in SwiftestModuleGraph.declarations {
            let directory: String
            switch declaration.role {
            case .test:
                directory = "Tests"
            case .plugin:
                directory = "Plugins"
            case .production, .executable, .macro:
                directory = "Sources"
            }
            let relative = directory + "/" + declaration.name
            let kind: FileEntryKind
            do {
                kind = try FileSystemBoundary.entryKind(path: root + "/" + relative)
            } catch {
                violations.append(violation(.unclassifiedTarget, file: relative, subject: "missing-target"))
                continue
            }
            if kind != .directory {
                violations.append(violation(.unclassifiedTarget, file: relative, subject: "not-directory"))
            }
        }
        for relative in importsByPath.keys.sorted() {
            guard let module = moduleName(relativePath: relative) else {
                continue
            }
            guard let declaration = declarations[module] else {
                continue
            }
            guard let imports = importsByPath[relative] else {
                continue
            }
            for imported in imports.sorted() {
                if SwiftestModuleGraph.permitsSystemImport(
                    imported,
                    declaration: declaration,
                    relativePath: relative
                ) {
                    continue
                }
                if SwiftestModuleGraph.recognizedSystemModules.contains(imported) {
                    violations.append(violation(.reverseDependency, file: relative, subject: imported))
                    continue
                }
                if imported.hasSuffix("Tests") && declaration.role != .test {
                    violations.append(violation(.testSupportImport, file: relative, subject: imported))
                    continue
                }
                if !declaration.dependencies.contains(imported) {
                    violations.append(violation(.reverseDependency, file: relative, subject: imported))
                }
                if module == "SwiftestDecision"
                    && (imported == "SwiftestScore"
                        || imported == "SwiftestPresentation"
                        || imported == "SwiftestUI") {
                    violations.append(violation(.reverseDependency, file: relative, subject: imported))
                }
            }
        }
        let productRoots: Set<String> = ["Swiftest", "SwiftestCLI", "SwiftestLaws", "SwiftestTesting"]
        var reachable = productRoots
        var changed = true
        while changed {
            changed = false
            for module in Array(reachable) {
                guard let declaration = declarations[module] else {
                    continue
                }
                let previousCount = reachable.count
                reachable.formUnion(declaration.dependencies)
                if reachable.count != previousCount {
                    changed = true
                }
            }
        }
        for declaration in SwiftestModuleGraph.declarations
            where declaration.role == .production && !reachable.contains(declaration.name) {
            violations.append(violation(
                .unreachableProduction,
                file: "Sources/" + declaration.name,
                subject: declaration.name
            ))
        }
        return violations
    }

    private static func importedModules(_ source: String) -> Set<String> {
        let tree = Parser.parse(source: source)
        let texts = Array(tree.tokens(viewMode: .sourceAccurate)).compactMap { token in
            isLiteralMaterial(token.tokenKind) ? nil : token.text
        }
        var imports = Set<String>()
        let selectiveKinds: Set<String> = ["typealias", "struct", "class", "enum", "protocol", "func", "var", "let"]
        for index in texts.indices where texts[index] == "import" && index + 1 < texts.count {
            let first = index + 1
            let moduleIndex = selectiveKinds.contains(texts[first]) ? first + 1 : first
            if moduleIndex < texts.count {
                imports.insert(texts[moduleIndex])
            }
        }
        return imports
    }

    private static func sourceFiles(root: String) -> SourceInventory {
        var inventory = SourceInventory()
        walk(path: root, root: root, inventory: &inventory)
        inventory.paths.sort()
        return inventory
    }

    private static func walk(path: String, root: String, inventory: inout SourceInventory) {
        let relative = relativePath(path, root: root)
        let kind: FileEntryKind
        do {
            kind = try FileSystemBoundary.entryKind(path: path)
        } catch {
            inventory.violations.append(violation(.unreadableSource, file: relative, subject: "entry"))
            return
        }
        switch kind {
        case .file:
            inventory.paths.append(path)
        case .directory:
            if SourceExclusionPolicy.excludesDirectory(relativePath: relative) {
                return
            }
            if !relative.isEmpty && !relative.contains("/") && !allowedTopLevelDirectories.contains(relative) {
                inventory.violations.append(violation(.unclassifiedSource, file: relative, subject: "directory"))
            }
            let entries: [String]
            do {
                entries = try FileSystemBoundary.list(path: path)
            } catch {
                inventory.violations.append(violation(.unreadableSource, file: relative, subject: "list"))
                return
            }
            for entry in entries {
                walk(path: path + "/" + entry, root: root, inventory: &inventory)
            }
        case .symbolicLink, .other:
            inventory.violations.append(violation(.unreadableSource, file: relative, subject: kind.rawValue))
        }
    }

    private static func shouldScan(_ path: String) -> Bool {
        let components = path.split(separator: "/")
        guard let root = components.first else {
            return false
        }
        if components.count == 1 {
            return allowedRootFiles.contains(path)
        }
        switch root {
        case "Sources", "Tests", "Plugins":
            return components.count >= 3 && path.hasSuffix(".swift")
        case "SwiftestProofs":
            return components.count == 2 && path.hasSuffix(".lean")
        case "Scripts":
            return components.count == 2 && allowedScripts.contains(String(components[1]))
        case ".githooks":
            return path == ".githooks/pre-push"
        case ".github":
            return components.count == 3
                && components[1] == "workflows"
                && (path.hasSuffix(".yml") || path.hasSuffix(".yaml"))
        case "Fixtures":
            guard components.count >= 4 && components[1] == "CompileFail" else {
                return false
            }
            if components.count == 4 {
                return components[3] == "Package.swift"
            }
            return components.count == 6
                && components[3] == "Sources"
                && components[4] == components[2]
                && path.hasSuffix(".swift")
        default:
            return false
        }
    }

    private static let allowedRootFiles: Set<String> = [
        ".gitignore", "LICENSE", "Package.swift", "SwiftestProofs.lean", "lake-manifest.json",
        "lakefile.toml", "lean-toolchain",
    ]

    private static let allowedScripts: Set<String> = [
        "compile-fail", "dogfood", "formal-check", "mutate-laws", "platform-check", "quality",
    ]

    private static let allowedTopLevelDirectories: Set<String> = [
        ".githooks", ".github", "Fixtures", "Plugins", "Scripts", "Sources", "SwiftestProofs", "Tests",
    ]

    private static func moduleName(relativePath: String) -> String? {
        let components = relativePath.split(separator: "/").map(String.init)
        if components.count < 2 {
            return nil
        }
        if components[0] == "Sources" || components[0] == "Tests" || components[0] == "Plugins" {
            return components[1]
        }
        return nil
    }

    private static func relativePath(_ path: String, root: String) -> String {
        if path == root {
            return ""
        }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return path
    }

    private static func commentText(_ trivia: TriviaPiece) -> String? {
        switch trivia {
        case .lineComment(let text),
            .blockComment(let text),
            .docLineComment(let text),
            .docBlockComment(let text):
            text
        default:
            nil
        }
    }

    private static func isAllowedComment(text: String, path: String, source: String, offset: Int) -> Bool {
        let location = locationIn(source: source, offset: offset)
        if path.hasSuffix("Package.swift")
            && source.hasPrefix(text)
            && text == "// swift-tools-version: 6.2" {
            return true
        }
        if text == "// SPDX-License-Identifier: Apache-2.0"
            || text == "// SPDX-License-Identifier: MIT" {
            if location.line == 1 && source.hasPrefix(text) {
                return true
            }
            return path.hasSuffix("Package.swift")
                && location.line == 2
                && source.hasPrefix("// swift-tools-version: 6.2\n" + text)
        }
        return false
    }

    private static func isAllowedOtherComment(_ comment: LexedComment, path: String) -> Bool {
        path.hasPrefix("Scripts/") && comment.offset == 0 && comment.text == "#!/bin/sh"
            || path.hasPrefix(".githooks/") && comment.offset == 0 && comment.text == "#!/bin/sh"
    }

    private static func commentKind(_ text: String) -> String {
        if text.hasPrefix("///") || text.hasPrefix("/**") {
            return "documentation-comment"
        }
        return "comment"
    }

    private static func isLiteralMaterial(_ kind: TokenKind) -> Bool {
        switch kind {
        case .stringQuote,
            .multilineStringQuote,
            .stringSegment,
            .rawStringPoundDelimiter,
            .regexLiteralPattern,
            .regexPoundDelimiter,
            .regexSlash:
            true
        default:
            false
        }
    }

    private static func isPolicyName(_ text: String) -> Bool {
        let names: Set<String> = [
            "allow",
            "enabled",
            "include",
            "isEnabled",
            "policy",
            "skip",
            "strict",
            "update",
            "useCache",
        ]
        return names.contains(text)
    }

    private static let libcFilesystemSymbols: Set<String> = [
        "openat", "creat", "fopen", "freopen", "fdopen", "fwrite", "pwrite",
        "writev", "pwritev", "unlink", "unlinkat", "rename", "renameat", "rmdir",
        "mkdir", "mkdirat", "symlink", "symlinkat", "linkat", "truncate",
        "ftruncate", "chmod", "chown", "fchmod", "fchown", "mknod", "mkfifo",
        "mkstemp", "mkdtemp", "copyfile", "fcopyfile", "clonefile", "exchangedata",
        "setxattr", "fsetxattr", "removexattr", "fremovexattr",
    ]

    private static let libcProcessSymbols: Set<String> = [
        "system", "popen", "fork", "vfork", "posix_spawn", "posix_spawnp",
        "execve", "execv", "execvp", "execl", "execlp",
    ]

    private static func containsSequence(_ sequence: [String], tokens: [TokenRecord]) -> Bool {
        containsCodeSequence(sequence, in: tokens.map(\.text))
    }

    private static func containsCodeSequence(_ sequence: [String], in tokens: [String]) -> Bool {
        if sequence.isEmpty || tokens.count < sequence.count {
            return false
        }
        for start in 0...(tokens.count - sequence.count) {
            var matches = true
            for offset in sequence.indices where tokens[start + offset] != sequence[offset] {
                matches = false
            }
            if matches {
                return true
            }
        }
        return false
    }

    private static func isFileScope(_ token: TokenSyntax) -> Bool {
        var node = Syntax(token)
        while let parent = node.parent {
            let kind = String(describing: parent.kind)
            if kind == "sourceFile" {
                return true
            }
            if kind == "memberBlock" || kind == "codeBlock" || kind == "closureExpr" {
                return false
            }
            node = parent
        }
        return false
    }

    private static func isTypeStaticVar(_ token: TokenSyntax) -> Bool {
        guard token.text == "var" else {
            return false
        }
        var node = Syntax(token)
        while let parent = node.parent {
            if let declaration = parent.as(VariableDeclSyntax.self) {
                return declaration.modifiers.contains { modifier in
                    modifier.name.text == "static" || modifier.name.text == "class"
                }
            }
            node = parent
        }
        return false
    }

    private static func at(
        _ law: LawCode,
        token: TokenRecord,
        source: String,
        path: String
    ) -> LawViolation {
        let point = locationIn(source: source, offset: token.offset)
        return LawViolation(
            law: law,
            location: SourceLocation(file: path, line: point.line, column: point.column),
            subject: token.text
        )
    }

    private static func violation(
        _ law: LawCode,
        file: String,
        subject: String
    ) -> LawViolation {
        LawViolation(
            law: law,
            location: SourceLocation(file: file, line: 1, column: 1),
            subject: subject
        )
    }

    private static func violation(
        _ law: LawCode,
        file: String,
        source: String,
        offset: Int,
        subject: String
    ) -> LawViolation {
        let point = locationIn(source: source, offset: offset)
        return LawViolation(
            law: law,
            location: SourceLocation(file: file, line: point.line, column: point.column),
            subject: subject
        )
    }

    private static func locationIn(source: String, offset: Int) -> (line: Int, column: Int) {
        let bytes = Array(source.utf8)
        let boundedOffset = min(max(offset, 0), bytes.count)
        var line = 1
        var column = 1
        for byte in bytes[0..<boundedOffset] {
            if byte == 10 {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }
        return (line, column)
    }
}

private struct TokenRecord {
    let text: String
    let offset: Int
    let isFileScope: Bool
    let isTypeStaticVar: Bool
    let isForceUnwrap: Bool
}

private struct SourceInventory {
    var paths: [String] = []
    var violations: [LawViolation] = []
}
