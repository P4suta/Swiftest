import SwiftestMutation
import Testing

@Test
func symbolicSILUnknownReturnedValueCannotProveIdentity() throws {
    let source = "%0 = argument 0\n%1 = opaque_transform %0\nreturn %1"
    #expect(try SymbolicSIL.compare(original: source, mutant: source) == .unknown)
}

@Test
func symbolicSILUnusedSideEffectsCannotBeIgnored() throws {
    let pure = "%0 = argument 0\nreturn %0"
    let sideEffect = "%0 = argument 0\napply %callback(%0)\nreturn %0"
    #expect(try SymbolicSIL.compare(original: pure, mutant: sideEffect) == .unknown)
    #expect(try SymbolicSIL.compare(original: sideEffect, mutant: sideEffect) == .unknown)
}

@Test
func symbolicSILUnknownControlFlowAndTrailingInstructionsCannotProveIdentity() throws {
    let pure = "%0 = argument 0\nreturn %0"
    let branch = "%0 = argument 0\ncond_br %0, bb1, bb2\nreturn %0"
    let trailingEffect = "%0 = argument 0\nreturn %0\napply %callback(%0)"
    let duplicateAssignment = "%0 = argument 0\n%0 = argument 1\nreturn %0"
    #expect(try SymbolicSIL.compare(original: pure, mutant: branch) == .unknown)
    #expect(try SymbolicSIL.compare(original: pure, mutant: trailingEffect) == .unknown)
    #expect(try SymbolicSIL.compare(original: pure, mutant: duplicateAssignment) == .unknown)
}
