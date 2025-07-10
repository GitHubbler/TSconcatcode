//# concatcode - Swift Command Line Tool
//
//## Package.swift
//
//```swift
//// swift-tools-version: 5.9
//import PackageDescription
//
//let package = Package(
//    name: "concatcode",
//    platforms: [
//        .macOS(.v10_15)
//    ],
//    products: [
//        .executable(
//            name: "concatcode",
//            targets: ["concatcode"]
//        ),
//    ],
//    targets: [
//        .executableTarget(
//            name: "concatcode",
//            dependencies: []
//        ),
//    ]
//)
//```
//
//## Sources/concatcode/main.swift
//
//```swift
import Foundation

struct ConcatCodeTool {
    let directories: [String]
    let outputPath: String
    
    func run() throws {
        let outputURL = URL(fileURLWithPath: outputPath)
        
        // Create output file (or truncate if exists)
        FileManager.default.createFile(atPath: outputPath, contents: nil, attributes: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer { outputHandle.closeFile() }
        
        for directory in directories {
            try processDirectory(directory, outputHandle: outputHandle)
        }
        
        print("Successfully concatenated code to: \(outputPath)")
    }
    
    private func processDirectory(_ directoryPath: String, outputHandle: FileHandle) throws {
        let directoryURL = URL(fileURLWithPath: directoryPath)
        var currentModuleName = directoryURL.lastPathComponent
        
        let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        
        guard let enumerator = enumerator else {
            throw ConcatCodeError.invalidDirectory(directoryPath)
        }
        
        // First pass: look for Package.swift files to determine module names
        var packageFiles: [URL] = []
        var otherFiles: [URL] = []
        
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            
            let fileName = fileURL.lastPathComponent
            
            if fileName == "Package.swift" {
                packageFiles.append(fileURL)
            } else if fileName.hasSuffix(".swift") || fileName == "Info.plist" {
                otherFiles.append(fileURL)
            }
        }
        
        // Sort files for consistent output
        packageFiles.sort { $0.path < $1.path }
        otherFiles.sort { $0.path < $1.path }
        
        // Process Package.swift files first to update module names
        for packageURL in packageFiles {
            if let moduleName = try extractModuleName(from: packageURL) {
                currentModuleName = moduleName
            }
        }
        
        // Process other files
        for fileURL in otherFiles {
            try processFile(fileURL, moduleName: currentModuleName, outputHandle: outputHandle)
        }
    }
    
    private func extractModuleName(from packageURL: URL) throws -> String? {
        let content = try String(contentsOf: packageURL, encoding: .utf8)
        
        // Look for pattern: name: "packagename" or name: 'packagename'
        let patterns = [
            #"name:\s*"([^"]+)""#,
            #"name:\s*'([^']+)'"#
        ]
        
        for pattern in patterns {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            
            if let match = regex.firstMatch(in: content, options: [], range: range),
               let nameRange = Range(match.range(at: 1), in: content) {
                return String(content[nameRange])
            }
        }
        
        return nil
    }
    
    private func processFile(_ fileURL: URL, moduleName: String, outputHandle: FileHandle) throws {
        let fileName = fileURL.lastPathComponent
        let relativePath = fileURL.path
        
        // Write module header
        let moduleHeader = "// module: \(moduleName)\n"
        outputHandle.write(moduleHeader.data(using: .utf8)!)
        
        // Write file header
        let fileHeader = "// file: \(fileName)\n"
        outputHandle.write(fileHeader.data(using: .utf8)!)
        
        // Write file contents
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        outputHandle.write(content.data(using: .utf8)!)
        
        // Ensure content ends with newline
        if !content.hasSuffix("\n") {
            outputHandle.write("\n".data(using: .utf8)!)
        }
        
        // Write end of file marker
        let endMarker = "// end of file: \(fileName)\n\n"
        outputHandle.write(endMarker.data(using: .utf8)!)
    }
}

enum ConcatCodeError: Error, LocalizedError {
    case invalidDirectory(String)
    case missingOutputPath
    case invalidArguments
    
    var errorDescription: String? {
        switch self {
        case .invalidDirectory(let path):
            return "Invalid directory: \(path)"
        case .missingOutputPath:
            return "Missing --output parameter"
        case .invalidArguments:
            return "Invalid arguments. Usage: concatcode <directory1> [directory2...] --output <output_file>"
        }
    }
}

// MARK: - Main Entry Point

func main() {
    let arguments = Array(CommandLine.arguments.dropFirst()) // Remove program name
    
    do {
        guard arguments.count >= 3 else {
            throw ConcatCodeError.invalidArguments
        }
        
        // Find --output parameter
        guard let outputIndex = arguments.firstIndex(of: "--output"),
              outputIndex + 1 < arguments.count else {
            throw ConcatCodeError.missingOutputPath
        }
        
        let outputPath = arguments[outputIndex + 1]
        let directories = Array(arguments[0..<outputIndex])
        
        guard !directories.isEmpty else {
            throw ConcatCodeError.invalidArguments
        }
        
        let tool = ConcatCodeTool(directories: directories, outputPath: outputPath)
        try tool.run()
        
    } catch {
        print("Error: \(error.localizedDescription)")
        print("Usage: concatcode <directory1> [directory2...] --output <output_file>")
        exit(1)
    }
}

main()
//```
//
//## Usage Examples
//
//```bash
//# Build the tool
//swift build -c release
//
//# Run examples
//./.build/release/concatcode /path/to/project1 --output /tmp/concatenated.swift
//
//./.build/release/concatcode ./Sources ./Tests --output ./output.swift
//
//./.build/release/concatcode /absolute/path/to/proj1 /absolute/path/to/proj2 --output /tmp/all_code.swift
//```
//
//## Features
//
//* **Recursive directory traversal**: Visits all subdirectories
//
//* **Module name detection**: Uses directory name initially, updates from Package.swift when found
//
//* **File filtering**: Only processes `*.swift` files and `Info.plist`, ignores `Package.swift` for output
//
//* **Proper headers**: Adds module, file, and end-of-file markers
//
//* **Error handling**: Provides clear error messages
//
//* **Sorted output**: Files are processed in consistent alphabetical order
//
//* **UTF-8 support**: Handles Swift source files with proper encoding
//
//The tool will create output like:
//
//```swift
//// module: MyProject
//// file: ContentView.swift
//import SwiftUI
//
//struct ContentView: View {
//    // ...
//}
//// end of file: ContentView.swift
//
//// module: MyProject
//// file: Info.plist
//<?xml version="1.0" encoding="UTF-8"?>
//// ...
//// end of file: Info.plist
//```
