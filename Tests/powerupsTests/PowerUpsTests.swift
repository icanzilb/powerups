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

import XCTest
import Foundation
import powerups

let comments = try! NSRegularExpression(pattern: "<!--[^>]+-->", options: [])
let whitespace = try! NSRegularExpression(pattern: ">\\s+<", options: [])
func minify(_ source: String) -> String {
    var result = comments
        .stringByReplacingMatches(in: source, options: .withTransparentBounds, range: NSRange(source.startIndex..., in: source), withTemplate: "")
        .components(separatedBy: .newlines)
        .joined(separator: "")
    result = whitespace
        .stringByReplacingMatches(in: result, options: .withTransparentBounds, range: NSRange(result.startIndex..., in: result), withTemplate: "><")
    return result
}

final class PowerUpsTests: XCTestCase {
    /// Verify the result for an empty source.
    func testEmptySource() throws {
        let source = try TempFile(content: "")
        let result = try PowerUps().run(arguments: [source.url.path])
        XCTAssertEqual(result, "")
    }

    /// Verify the result for a given static text.
    func testEmptyStatic() throws {
        let source = try TempFile(content: "Some content")
        let result = try PowerUps().run(arguments: [source.url.path])
        XCTAssertEqual(result, "Some content")
    }

    /// Verify including non-existing file throws.
    func testIncludeNotFound() throws {
        let source = try TempFile(content: "<root> <!-- include \"test.xml\" --> </root>")
        XCTAssertThrowsError(try PowerUps().run(arguments: [
            source.url.path,
            "--includesFolder",
            NSTemporaryDirectory()
        ]))
    }

    /// Verify undefined global variables are not replaced in included files.
    func testGlobalVariablesUndefined() throws {
        let include = try TempFile(content: "<block>${variable}</block>")
        let source = try TempFile(content: "<root> <!-- include \"\(include.url.lastPathComponent)\" --> </root>")
        let result = try PowerUps().run(arguments: [
            source.url.path,
            "--includesFolder",
            NSTemporaryDirectory()
        ])
        XCTAssertEqual(minify(result), "<root><block>${variable}</block></root>")
    }

    /// Verify global variables are replaced in included files.
    func testGlobalVariablesDefined() throws {
        let include = try TempFile(content: "<block>${variable}</block>")
        let source = try TempFile(content:
            """
            <root>
                <!-- include \"\(include.url.lastPathComponent)\" -->
            </root>
            """
        )
        let globals = try TempFile(content: "{\"variable\":\"Hello\"}")
        let result = try PowerUps().run(arguments: [
            source.url.path,
            "--includesFolder",
            NSTemporaryDirectory(),
            "--variables",
            globals.url.path
        ])
        XCTAssertEqual(minify(result), "<root><block>Hello</block></root>")
    }

    /// Verify include variables are replaced in included files.
    func testLocalVariablesDefined() throws {
        let include = try TempFile(content: "<block>${variable}</block>")
        let source = try TempFile(content:
            """
            <root>
                <!-- include \"\(include.url.lastPathComponent)\" variable=\"111\" -->
                <!-- include \"\(include.url.lastPathComponent)\" variable=\"222\" -->
            </root>
            """
        )
        let result = try PowerUps().run(arguments: [
            source.url.path,
            "--includesFolder",
            NSTemporaryDirectory()
        ])
        XCTAssertEqual(minify(result), "<root><block>111</block><block>222</block></root>")
    }

    /// Verify `capitalized` modifier, capitalizes variables.
    func testCapitalized() throws {
        let include = try TempFile(content: "<block>${variable.capitalized}</block>")
        let source = try TempFile(content:
            """
            <root>
                <!-- include \"\(include.url.lastPathComponent)\" -->
            </root>
            """
        )
        let globals = try TempFile(content: "{\"variable\":\"hello\"}")
        let result = try PowerUps().run(arguments: [
            source.url.path,
            "--includesFolder",
            NSTemporaryDirectory(),
            "--variables",
            globals.url.path
        ])
        XCTAssertEqual(minify(result), "<root><block>Hello</block></root>")
    }

    /// Verify includes can be nested.
    func testNested() throws {
        let nested = try TempFile(content: "<nested>${nestedVariable}</nested>")
        let include = try TempFile(
            content:
                """
                <block>
                    <!-- include \"\(nested.url.lastPathComponent)\" nestedVariable=\"${variable}\" -->
                </block>
                """
        )
        let source = try TempFile(content:
            """
            <root>
                <!-- include \"\(include.url.lastPathComponent)\" -->
            </root>
            """
        )
        let globals = try TempFile(content: "{\"variable\":\"Hello\"}")
        let result = try PowerUps().run(arguments: [
            source.url.path,
            "--includesFolder",
            NSTemporaryDirectory(),
            "--variables",
            globals.url.path
        ])
        XCTAssertEqual(minify(result), "<root><block><nested>Hello</nested></block></root>")
    }

    /// Verify includes respect false `where` condition.
    func testNestedConditionallyFalse() throws {
        let nested = try TempFile(content: "<nested>${nestedVariable}</nested>")
        let include = try TempFile(
            content:
                """
                <block>
                    <!-- include \"\(nested.url.lastPathComponent)\" where \"${variable}==test\" nestedVariable=\"${variable}\" -->
                </block>
                """
        )
        let source = try TempFile(content:
            """
            <root>
                <!-- include \"\(include.url.lastPathComponent)\" -->
            </root>
            """
        )
        let globals = try TempFile(content: "{\"variable\":\"Hello\"}")
        let result = try PowerUps().run(arguments: [
            source.url.path,
            "--includesFolder",
            NSTemporaryDirectory(),
            "--variables",
            globals.url.path
        ])
        XCTAssertEqual(minify(result), "<root><block></block></root>")
    }

    /// Verify includes respect true `where` condition.
    func testNestedConditionallyTrue() throws {
        let nested = try TempFile(content: "<nested>${nestedVariable}</nested>")
        let include = try TempFile(
            content:
                """
                <block>
                    <!-- include \"\(nested.url.lastPathComponent)\" where \"${variable}==Hello\" nestedVariable=\"${variable}\" -->
                </block>
                """
        )
        let source = try TempFile(content:
            """
            <root>
                <!-- include \"\(include.url.lastPathComponent)\" -->
            </root>
            """
        )
        let globals = try TempFile(content: "{\"variable\":\"Hello\"}")
        let result = try PowerUps().run(arguments: [
            source.url.path,
            "--includesFolder",
            NSTemporaryDirectory(),
            "--variables",
            globals.url.path
        ])
        XCTAssertEqual(minify(result), "<root><block><nested>Hello</nested></block></root>")
    }

    /// Verify the source isn't modified.
    func testSourceFileUnmodified() throws {
        let include = try TempFile(content: "<block>${variable}</block>")
        let sourceString =
                    """
                    <root>
                        <!-- include \"\(include.url.lastPathComponent)\" -->
                    </root>
                    """
        let source = try TempFile(content: sourceString)
        let globals = try TempFile(content: "{\"variable\":\"Hello\"}")

        let result = try PowerUps().run(arguments: [
            source.url.path,
            "--includesFolder",
            NSTemporaryDirectory(),
            "--variables",
            globals.url.path
        ])

        XCTAssertEqual(try String(contentsOf: source.url), sourceString)
        XCTAssertNotEqual(try String(contentsOf: source.url), result)
    }

    /// Verify the source is modified.
    func testSourceFileModified() throws {
        let include = try TempFile(content: "<block>${variable}</block>")
        let sourceString =
                    """
                    <root>
                        <!-- include \"\(include.url.lastPathComponent)\" -->
                    </root>
                    """
        let source = try TempFile(content: sourceString)
        let globals = try TempFile(content: "{\"variable\":\"Hello\"}")

        let result = try PowerUps().run(arguments: [
            source.url.path,
            "--includesFolder",
            NSTemporaryDirectory(),
            "--variables",
            globals.url.path,
            "--overwrite"
        ])

        XCTAssertNotEqual(try String(contentsOf: source.url), sourceString)
        XCTAssertEqual(try String(contentsOf: source.url), result)
    }
}
