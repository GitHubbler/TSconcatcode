import Foundation
import ArgumentParser

@main
struct ConcatCode: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A Swift CLT to concatenate Swift source files from multiple modules into a single file.",
        version: "1.1.0" // Updated version
    )

    @Argument(help: "One or more directory paths to scan for source files.")
    var directoryPaths: [String]

    @Option(name: .shortAndLong, help: "The absolute or relative path for the output file.")
    var output: String

    /// Runs the command logic.
    func run() throws {
        let outputURL = URL(fileURLWithPath: output)
        
        // Ensure the output directory exists
        let outputDir = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Create or truncate the output file
        guard let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
            throw CleanExit.message("Error: Could not open file handle for output at \(outputURL.path)")
        }
        // Ensure the file is empty before we start
        outputHandle.truncateFile(atOffset: 0)
        
        defer {
            do {
                try outputHandle.close()
            } catch {
                print("Warning: Could not close file handle: \(error.localizedDescription)")
            }
        }

        for path in directoryPaths {
            let directoryURL = URL(fileURLWithPath: path).standardized
            try processDirectory(url: directoryURL, outputHandle: outputHandle)
        }
        
        print("✅ Concatenation complete. Output written to \(outputURL.path)")
    }

    /// Processes a single top-level directory provided as a command-line argument.
    private func processDirectory(url: URL, outputHandle: FileHandle) throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            print("Warning: Could not create enumerator for path \(url.path). Skipping.")
            return
        }

        print("Processing directory tree at \(url.path)...")

        for case let fileURL as URL in enumerator {
            guard try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            
            let fileName = fileURL.lastPathComponent
            
            // Criteria check
            if fileName != "Package.swift" && (fileName.hasSuffix(".swift") || fileName == "Info.plist") {
                // For each file, find its specific module name by searching upwards for Package.swift
                let moduleName = findModuleName(for: fileURL, relativeTo: url)
                try appendFileContents(from: fileURL, moduleName: moduleName, to: outputHandle)
            }
        }
    }

    /// Determines the module name for a given file by searching up the directory tree for `Package.swift`.
    /// - Parameters:
    ///   - fileURL: The URL of the source file being processed.
    ///   - topLevelURL: The top-level directory of the scan, used as a boundary.
    /// - Returns: The name of the module the file belongs to.
    private func findModuleName(for fileURL: URL, relativeTo topLevelURL: URL) -> String {
        var currentURL = fileURL.deletingLastPathComponent()

        // Walk up the directory tree from the file's location
        while currentURL.path.count >= topLevelURL.path.count && currentURL.path.hasPrefix(topLevelURL.path) {
            let packageFileURL = currentURL.appendingPathComponent("Package.swift")
            
            if let packageName = parsePackageName(from: packageFileURL) {
                return packageName
            }
            
            // Stop if we are at the top-level directory itself and have checked it
            if currentURL.path == topLevelURL.path {
                break
            }
            
            currentURL.deleteLastPathComponent()
        }
        
        // If no Package.swift was found in the ancestry, default to the top-level directory's name.
        return topLevelURL.lastPathComponent
    }

    /// Parses a `Package.swift` file to find the package name.
    private func parsePackageName(from packageFileURL: URL) -> String? {
        guard let content = try? String(contentsOf: packageFileURL, encoding: .utf8) else {
            return nil
        }
        
        // A simple line-by-line search for the name parameter.
        for line in content.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("name:") {
                let components = trimmedLine.split(separator: ":", maxSplits: 1)
                if components.count == 2 {
                    return components[1]
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
        }
        return nil
    }

    /// Appends the formatted content of a single source file to the output handle.
    private func appendFileContents(from fileURL: URL, moduleName: String, to outputHandle: FileHandle) throws {
        let fileName = fileURL.lastPathComponent
        let fileContents = try String(contentsOf: fileURL, encoding: .utf8)

        let header = """
        // module: \(moduleName)
        // file: \(fileName)
        """
        
        let footer = "// end of file: \(fileName)\n\n"
        
        let fullBlock = "\(header)\n\(fileContents)\n\(footer)"

        if let data = fullBlock.data(using: .utf8) {
            try outputHandle.write(contentsOf: data)
        }
    }
}
