//
//  ConcatCode.swift
//  concatcode
//
//  Created by Pierre van Aswegen on 2025-07-10.
//


import Foundation
import ArgumentParser

@main
struct ConcatCode: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A Swift CLT to concatenate Swift source files from multiple modules into a single file.",
        version: "1.0.0"
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
            let directoryURL = URL(fileURLWithPath: path)
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

        let moduleName = findModuleName(in: url)
        print("Processing module '\(moduleName)' from path \(url.path)...")

        for case let fileURL as URL in enumerator {
            guard try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            
            let fileName = fileURL.lastPathComponent
            
            // Criteria check
            if fileName != "Package.swift" && (fileName.hasSuffix(".swift") || fileName == "Info.plist") {
                try appendFileContents(from: fileURL, moduleName: moduleName, to: outputHandle)
            }
        }
    }

    /// Determines the module name for a given directory.
    /// It prioritizes the name from `Package.swift` if found, otherwise uses the directory name.
    private func findModuleName(in directoryURL: URL) -> String {
        let packageFileURL = directoryURL.appendingPathComponent("Package.swift")
        if let packageName = parsePackageName(from: packageFileURL) {
            return packageName
        }
        return directoryURL.lastPathComponent
    }

    /// Parses a `Package.swift` file to find the package name.
    private func parsePackageName(from packageFileURL: URL) -> String? {
        guard let content = try? String(contentsOf: packageFileURL, encoding: .utf8) else {
            return nil
        }
        
        // A simple but effective line-by-line search for the name parameter.
        // This is more resilient than a complex regex for this specific case.
        for line in content.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("name:") {
                // Extracts the value from 'name: "MyPackage"'
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
