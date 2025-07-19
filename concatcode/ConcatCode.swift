import Foundation
import ArgumentParser

@main
struct ConcatCode: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A Swift CLT to concatenate Swift source files from multiple modules into a single file.",
        version: "1.2.1"
    )

    @Argument(help: "One or more directory paths to scan for source files.")
    var directoryPaths: [String]

    @Option(name: .shortAndLong, help: "The absolute or relative path for the output file.")
    var output: String

    /// Runs the command logic.
    func run() throws {
        let outputURL = URL(fileURLWithPath: output)
        let fileManager = FileManager.default
        
        // Ensure the output directory exists
        let outputDir = outputURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // If the output file does not exist, create it before attempting to open a handle.
        // This is the necessary step to fix the crash with new files.
        if !fileManager.fileExists(atPath: outputURL.path) {
            guard fileManager.createFile(atPath: outputURL.path, contents: nil, attributes: nil) else {
                throw CleanExit.message("Error: Failed to create output file at \(outputURL.path). Check permissions.")
            }
        }

        // Now that the file is guaranteed to exist, this call will succeed.
        guard let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
            throw CleanExit.message("Error: Could not open file handle for output at \(outputURL.path)")
        }
        // This line correctly clears the file for a fresh run.
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
            
            if fileName != "Package.swift"
                && fileName != "TaxonBrowserView.swift"
                && fileName != "KewProcessor.swift"
                && fileName != "WFOProcessor.swift"
                && fileName != "WFOTaxonDetailsFileDocument.swift"
                && fileName != "KewProcessor"
                && (
                fileName.hasSuffix(".swift")
                || fileName == "Info.plist"
                || fileName == "README.md"
                || fileName == "PLAN.md"
            ) {
                let moduleName = findModuleName(for: fileURL, relativeTo: url)
                try appendFileContents(from: fileURL, moduleName: moduleName, to: outputHandle)
            }
        }
    }

    private func findModuleName(for fileURL: URL, relativeTo topLevelURL: URL) -> String {
        var currentURL = fileURL.deletingLastPathComponent()

        while currentURL.path.count >= topLevelURL.path.count && currentURL.path.hasPrefix(topLevelURL.path) {
            let packageFileURL = currentURL.appendingPathComponent("Package.swift")
            
            if let packageName = parsePackageName(from: packageFileURL) {
                return packageName
            }
            
            if currentURL.path == topLevelURL.path {
                break
            }
            
            currentURL.deleteLastPathComponent()
        }
        
        return topLevelURL.lastPathComponent
    }

    private func parsePackageName(from packageFileURL: URL) -> String? {
        guard let content = try? String(contentsOf: packageFileURL, encoding: .utf8) else {
            return nil
        }
        
        for line in content.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("name:") {
                let components = trimmedLine.split(separator: ":", maxSplits: 1)
                if components.count == 2 {
                    return components[1]
                        .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\",")))
                }
            }
        }
        return nil
    }

    private func appendFileContents(from fileURL: URL, moduleName: String, to outputHandle: FileHandle) throws {
        let fileName = fileURL.lastPathComponent
        let rawFileContents = try String(contentsOf: fileURL, encoding: .utf8)

        let filteredLines = rawFileContents.components(separatedBy: .newlines).filter { line in
            !line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
        }
        let fileContents = filteredLines.joined(separator: "\n")

        guard !fileContents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let header = """
        // module: \(moduleName)
        // file: \(fileName)
        """
        
        let footer = "// end of file: \(fileName)\n\n"
        
        let fullBlock = "\(header)\n\(fileContents)\n\(footer)"

        if let data = fullBlock.data(using: .utf8) {
            outputHandle.write(data)
        }
    }
}
