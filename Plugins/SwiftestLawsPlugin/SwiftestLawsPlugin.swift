import PackagePlugin

@main
struct SwiftestLawsPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command] {
        let tool = try context.tool(named: "SwiftestLawTool")
        let output = context.pluginWorkDirectoryURL.appending(path: "laws.stamp")
        let inputs = try PluginInputInventory.collect(root: context.package.directoryURL)
        return [
            .buildCommand(
                displayName: "Swiftest laws for " + target.name,
                executable: tool.url,
                arguments: [context.package.directoryURL.path, output.path] + inputs.map(\.relativePath),
                inputFiles: inputs.map(\.url),
                outputFiles: [output]
            )
        ]
    }
}
