import Foundation
import PackagePlugin

@main
struct OwnIDModuleVersion: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let input = context.package.directoryURL.appendingPathComponent("sdk-version.xcconfig")
        let output = context.pluginWorkDirectoryURL.appendingPathComponent("sdk-version.xcconfig")
        return [
            .buildCommand(
                displayName: "Copy \(target.name) version resource",
                executable: URL(fileURLWithPath: "/bin/cp"),
                arguments: [input.path, output.path],
                inputFiles: [input],
                outputFiles: [output]
            )
        ]
    }
}
