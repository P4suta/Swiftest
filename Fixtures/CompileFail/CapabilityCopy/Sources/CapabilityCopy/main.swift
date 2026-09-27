import Swiftest

func consume(_ capability: consuming WriteCapability) {}

func duplicateCapability() throws {
    let capability = try FileSystemAuthority.grant(root: "/private/tmp")
    consume(capability)
    consume(capability)
}

try duplicateCapability()
