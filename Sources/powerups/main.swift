// MIT License
//
// Copyright (c) 2022 Marin Todorov
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation

let envURL = URL(fileURLWithPath: "/usr/bin/env")

public struct PowerUps {
    var print: (Any) -> Void = { Swift.print($0) }

	/// Runs an external process.
	func runTask(
        _ url: URL,
        directory: URL? = nil,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) throws {
		let task = Process()
		task.currentDirectoryURL = directory
		task.executableURL = url
		task.arguments = arguments
		task.environment = ProcessInfo.processInfo.environment.merging(environment, uniquingKeysWith: +)
		task.launch()
		task.waitUntilExit()

		guard task.terminationStatus == 0 else {
			throw "Exit status (\(task.terminationStatus)) \(task.terminationReason)"
		}
	}

	static let usage = "\n\nUsage: powerups [target file] --includesFolder [includes directory] --variables [variables.json]\n\n"

	/// Run the main CLI workflow.
	public static func main(arguments: [String]) throws {
        Swift.print("Invocation:")
        arguments.forEach({ Swift.print("  \($0)") })

        // Print usage.
        if arguments.count < 1 || arguments.firstIndex(of: "--help") != nil {
            Swift.print(usage)
            return
        }

        try Self().run(arguments: arguments)
    }

    public init() { }

    @discardableResult
    public func run(arguments: [String]) throws -> String {
		let targetURL = URL(fileURLWithPath: arguments[0])
		print("File: \(targetURL.path)")

		var text = try String(contentsOf: targetURL)

		// Clean up generated content
		if let _ = arguments.firstIndex(of: "--cleanup") {
			text = cleanup(text)
		}

		// Variables
		var variables = [String: String]()
		if let varsIndex = arguments.firstIndex(of: "--variables") {
			// Grab the variables file
			guard varsIndex.advanced(by: 1) < arguments.count else {
                throw "Specify source JSON file.\(Self.usage)"
			}
			let varsURL = URL(fileURLWithPath: arguments[varsIndex.advanced(by: 1)])
			print("Global variables: \(varsURL.path)")

			let decoder = JSONDecoder()
			variables = try decoder.decode([String: String].self, from: Data(contentsOf: varsURL))
		}

		// Includes folder
		if let sourceIndex = arguments.firstIndex(of: "--includesFolder") {
			// Replace original source with temp folder
			guard sourceIndex.advanced(by: 1) < arguments.count else {
                throw "Specify source folder.\(Self.usage)"
			}

			let sourceBundleURL = URL(fileURLWithPath: arguments[sourceIndex.advanced(by: 1)])
			print("Includes folder: \(sourceBundleURL.path)")

			var fileList = [String: URL]()
			files(in: sourceBundleURL)
				.forEach { url in
					fileList[url.lastPathComponent] = url
				}

			text = try includes(text, sourceURLs: fileList, variables: variables)
		}

		if let _ = arguments.firstIndex(of: "--overwrite") {
			print("Overwrites source file")
			try text.write(to: targetURL, atomically: true, encoding: .utf8)
		} else {
			print("---------------------------------")
			print(text)
		}

        return text
	}

	func files(in url: URL) -> [URL] {
		var files = [URL]()
		if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
			for case let fileURL as URL in enumerator {
				do {
					let fileAttributes = try fileURL.resourceValues(forKeys:[.isRegularFileKey])
					if fileAttributes.isRegularFile! {
						files.append(fileURL)
					}
				} catch {
                    print("\(fileURL.path): \(error)")
                }
			}
		}
		return files
	}

	func cleanup(_ text: String) -> String {
		var text = text
		let generatedTags = text.match("([ \t]+)<!-- included \"([^\"]+)\" \"([^\"]+)\" -->")
		for tag in generatedTags {
			guard var openingGeneratedIndex = text.index(of: tag[0]) else {
				continue
			}
			while text[text.index(openingGeneratedIndex, offsetBy: -1)] == "\n" {
				openingGeneratedIndex = text.index(openingGeneratedIndex, offsetBy: -1)
			}

			let closingGeneratedTag = "<!-- / included \"\(tag[2])\" \"\(tag[3])\" -->"
			guard let closingGeneratedIndex = text.index(of: closingGeneratedTag) else {
				continue
			}
			text.replaceSubrange(openingGeneratedIndex...text.index(closingGeneratedIndex, offsetBy: closingGeneratedTag.count), with: "")
		}
		return text
	}

	func parseParameters(from text: String) -> (params: [String: String], variables: [String: String]) {
		var result = [String: String]()
		let parts = text
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.components(separatedBy: .whitespaces)

		for param in ["include", "variables", "where"] {
			if let keyIndex = parts.firstIndex(of: param),
			   keyIndex + 1 < parts.count {
				var value = parts[keyIndex + 1]
				if value.hasPrefix("\"") && value.hasSuffix("\"") {
					value = String(value[value.index(after: value.startIndex)..<value.index(before: value.endIndex)])
				}
				result[param] = value
			}
		}

		var variables = [String: String]()
		for param in parts {
			if param.contains("=") {
				let sides = param.components(separatedBy: "=")
				guard sides.count > 1 else { continue }
				var value = sides[1]
				if value.hasPrefix("\"") && value.hasSuffix("\"") {
					value = String(value[value.index(after: value.startIndex)..<value.index(before: value.endIndex)])
				}
				variables[sides[0]] = value
			}
		}

		return (result, variables)
	}

	func includes(_ text: String, sourceURLs: [String: URL], variables: [String: String], isNestedInclude: Bool = false) throws -> String {
		var text = text

		// Remove generated content
		if !isNestedInclude {
			text = cleanup(text)
		}

		//let includeTags = text.match("([ \t]+)<!-- include \"([^\"]+)\"\\s*-->")
		let includeTags = text.match("([ \t]*)<!-- (include .*?)-->")

		// TODO: check for file name duplicates

		for tag in includeTags {
			let (params, bindings) = parseParameters(from: tag[2])
			guard let fileName = params["include"] else {
				continue
			}
			var localVariables = variables.merging(bindings, uniquingKeysWith: +)
			if let variablesFileName = params["variables"], let variablesURL = sourceURLs[variablesFileName] {
				let decoder = JSONDecoder()
				let includeVariables = try decoder.decode([String: String].self, from: Data(contentsOf: variablesURL))

				localVariables.merge(includeVariables, uniquingKeysWith: +)
			}

			let offset = tag[1]

			let id = UUID().uuidString
			let openingTag = "<!-- included \"\(fileName)\" \"\(id)\" -->"
			let closingTag = "<!-- / included \"\(fileName)\" \"\(id)\" -->"

			print("Include file: \(fileName) \(params["variables"] != nil ? "vars: \(params["variables"]!)" : "")")

			if let openingTagIndex = text.index(of: tag[0]) {
				let openingReplaceIndex = text.index(openingTagIndex, offsetBy: tag[0].count)

				guard let fileURL = sourceURLs[fileName] else {
					throw "\(fileName) not found!"
				}

				if let condition = params["where"], condition.contains("==") {
					let sides = condition.components(separatedBy: "==")
					guard sides[0].trimmingCharacters(in: .whitespaces) == sides[1].trimmingCharacters(in: .whitespaces) else {
						continue
					}
				}

				var replacement = try String(contentsOf: fileURL)

				for (name, value) in localVariables {
					replacement = replacement.replacingOccurrences(of: "${\(name)}", with: value)

					// Functions
					let functionCalls = replacement.match("\\$\\{\(name)\\.(\\w+)\\}")
					for call in functionCalls {
						switch call[1] {
						case "capitalized":
							replacement = replacement.replacingOccurrences(of: "${\(name).\(call[1])}", with: value.capitalized)
						default: break
						}
					}
				}

				// Nested includes
				replacement = try includes(replacement, sourceURLs: sourceURLs, variables: localVariables, isNestedInclude: true)

				replacement = "\n" + replacement
					.components(separatedBy: .newlines)
					.map { "\(offset)  \($0)" }
					.joined(separator: "\n")

				if !isNestedInclude {
					replacement += "\n\(offset)\(closingTag)\n"
					replacement = "\n\(offset)\(openingTag)\n\(replacement)"
				}

				text.insert(contentsOf: replacement, at: openingReplaceIndex)
			}
		}

		return text
	}
}

let main: Void = {
	do {
		try PowerUps.main(arguments: Array(CommandLine.arguments[1...]))
	} catch {
		print(error)
		exit(1)
	}
}()
