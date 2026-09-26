import SwiftestLaws
import Testing

@Test
func everyLawHasExactlyOneLegalAndIllegalFixture() {
    #expect(LawFixtureCatalog.all.count == LawCode.allCases.count)
    #expect(Set(LawFixtureCatalog.all.map(\.law)) == Set(LawCode.allCases))
    for fixture in LawFixtureCatalog.all {
        #expect(!fixture.legal.isEmpty)
        #expect(!fixture.illegal.isEmpty)
        #expect(fixture.legal != fixture.illegal)
    }
}

@Test
func syntacticLawFixturesDetectOnlyIllegalForms() {
    let syntactic: Set<LawCode> = [
        .forbiddenComment,
        .unreadableSource,
        .prohibitedTry,
        .forceUnwrap,
        .forceCast,
        .stringError,
        .ignoredResult,
        .semanticDefault,
        .optionalBoolean,
        .policyBoolean,
        .defaultClosedDomain,
        .handwrittenCases,
        .uninspectedMacro,
        .rawProcess,
        .detachedTask,
        .globalMutableState,
        .ownedExistential,
        .anyType,
        .mirror,
        .uncheckedArithmetic,
        .directEnvironment,
        .directClock,
        .directRandomness,
        .directFileWrite,
        .unsafeOutsideBoundary,
    ]
    for fixture in LawFixtureCatalog.all where syntactic.contains(fixture.law) {
        let legalPath = fixture.law == .uninspectedMacro
            ? "Sources/SwiftestTesting/Macros.swift"
            : "Sources/Fixture/Fixture.swift"
        let legal = LawScanner.scanSwiftSource(fixture.legal, path: legalPath)
        #expect(!legal.contains(where: { $0.law == fixture.law }))
        let illegal = LawScanner.scanSwiftSource(
            fixture.illegal,
            path: "Sources/Fixture/Fixture.swift"
        )
        #expect(illegal.contains(where: { $0.law == fixture.law }))
    }
}

@Test
func commentAndOperatorSymbolsInsideStringsAreNeverCode() {
    let source = "let text = \"// try? value! Process() Any Mirror &+ ??\"\n"
    let violations = LawScanner.scanSwiftSource(source, path: "Sources/Fixture/Fixture.swift")
    #expect(violations.isEmpty)
}

@Test
func logicalNegationIsNotForceUnwrap() {
    let source = "func check(_ value: Bool) -> Bool { !value }\n"
    let violations = LawScanner.scanSwiftSource(source, path: "Sources/Fixture/Fixture.swift")
    #expect(!violations.contains(where: { $0.law == .forceUnwrap }))
}
