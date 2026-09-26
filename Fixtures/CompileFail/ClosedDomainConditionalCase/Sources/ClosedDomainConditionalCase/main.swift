import SwiftestTesting

@ClosedDomain
enum InvalidDomain {
    #if os(macOS)
    case platformSpecific
    #endif
    case portable
}
