import Foundation
import Testing
@testable import RunwrightCore

/// A folder of fake tools: empty files marked executable (or not).
private func toolFolder(_ tools: [String], executable: Bool = true) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("runwright-tools-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for tool in tools {
        let url = dir.appendingPathComponent(tool)
        try Data().write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
    }
    return dir
}

@Suite struct TerminalToolsTests {
    @Test func findsTheFirstExecutableOnThePath() throws {
        let first = try toolFolder(["node"])
        let second = try toolFolder(["node", "cargo"])
        let path = "\(first.path):\(second.path)"
        #expect(TerminalTools.find("node", in: path) == first.appendingPathComponent("node").path)
        #expect(TerminalTools.find("cargo", in: path) == second.appendingPathComponent("cargo").path)
        #expect(TerminalTools.find("flutter", in: path) == nil)
    }

    @Test func ignoresFilesThatAreNotExecutable() throws {
        let dir = try toolFolder(["go"], executable: false)
        #expect(TerminalTools.find("go", in: dir.path) == nil)
    }

    @Test func dedupesPath() {
        #expect(TerminalTools.dedupe("/a:/b::/a:/c") == "/a:/b:/c")
        #expect(TerminalTools.dedupe("") == "")
        #expect(TerminalTools.dedupe(":/a:") == "/a")
    }

    @Test func listsToolsOnlyTheTerminalHas() throws {
        let terminal = try toolFolder(["flutter", "node", "cargo", "not-watched"])
        let jobs = try toolFolder(["node"])
        let missing = TerminalTools.missingTools(jobPath: jobs.path, terminalPath: "\(terminal.path):\(jobs.path)")
        // Watched tools only, in the watched order.
        #expect(missing == ["flutter", "cargo"])
    }

    @Test func nothingIsMissingWithoutATerminalPath() throws {
        let jobs = try toolFolder([])
        #expect(TerminalTools.missingTools(jobPath: jobs.path, terminalPath: nil).isEmpty)
    }
}
