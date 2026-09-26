import Testing

@attached(peer)
public macro WorldTest(
    _ displayName: _const String? = nil,
    _ traits: any TestTrait...
) = #externalMacro(module: "TestingMacros", type: "TestDeclarationMacro")

@attached(peer)
public macro WorldUITest(
    _ displayName: _const String? = nil,
    _ traits: any TestTrait...
) = #externalMacro(module: "TestingMacros", type: "TestDeclarationMacro")

@attached(peer)
public macro Property(
    _ displayName: _const String? = nil,
    _ traits: any TestTrait...
) = #externalMacro(module: "TestingMacros", type: "TestDeclarationMacro")

@attached(peer)
public macro StateMachineTest(
    _ displayName: _const String? = nil,
    _ traits: any TestTrait...
) = #externalMacro(module: "TestingMacros", type: "TestDeclarationMacro")

@attached(peer)
public macro PerformanceClaim(
    _ displayName: _const String? = nil,
    _ traits: any TestTrait...
) = #externalMacro(module: "TestingMacros", type: "TestDeclarationMacro")

@attached(peer)
public macro TestDouble() = #externalMacro(module: "TestingMacros", type: "PragmaMacro")

@attached(peer)
public macro ClosedDomain() = #externalMacro(module: "TestingMacros", type: "PragmaMacro")

@freestanding(expression)
public macro eventually(
    _ condition: Bool,
    _ comment: @autoclosure () -> Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) = #externalMacro(module: "TestingMacros", type: "ExpectMacro")

@freestanding(expression)
public macro invariant(
    _ condition: Bool,
    _ comment: @autoclosure () -> Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) = #externalMacro(module: "TestingMacros", type: "ExpectMacro")

@freestanding(expression)
public macro never(
    _ condition: Bool,
    _ comment: @autoclosure () -> Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) = #externalMacro(module: "TestingMacros", type: "ExpectMacro")
