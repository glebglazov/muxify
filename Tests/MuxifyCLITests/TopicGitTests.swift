import Foundation
import XCTest
@testable import MuxifyCLI

/// `topic status` and `topic diff` read real repositories: a clone of a bare origin, so that upstream, ahead and
/// behind are what git reports.
final class TopicGitTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        let made = FileManager.default.temporaryDirectory.appendingPathComponent("mxg-" + UUID().uuidString.prefix(8))
        try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
        root = made.resolvingSymlinksInPath()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testACleanCloneIsOnItsBranchWithItsUpstreamAndNoChanges() throws {
        let clone = try makeClone()
        let status = try GitStatus.read(try XCTUnwrap(try Git.repository(holding: clone)), base: nil)
        XCTAssertEqual(status.branch, "main")
        XCTAssertEqual(status.commit, try git(["rev-parse", "HEAD"], in: clone))
        XCTAssertEqual(status.upstream, "origin/main")
        XCTAssertEqual(status.ahead, 0)
        XCTAssertEqual(status.behind, 0)
        XCTAssertEqual(status.changes, [])
        XCTAssertEqual(status.shortLines, ["## main...origin/main"])
    }

    func testADirtyCloneListsEachChangedStagedRenamedAndUntrackedFile() throws {
        let clone = try makeClone()
        try write("changed\n", to: clone + "/readme.txt")
        try write("staged\n", to: clone + "/staged.txt")
        _ = try git(["add", "staged.txt"], in: clone)
        _ = try git(["mv", "old name.txt", "new name.txt"], in: clone)
        try FileManager.default.createDirectory(atPath: clone + "/notes", withIntermediateDirectories: true)
        try write("new\n", to: clone + "/notes/todo.txt")

        let status = try GitStatus.read(try XCTUnwrap(try Git.repository(holding: clone + "/notes")), base: nil)
        XCTAssertEqual(status.changes, [
            .init(kind: .renamed, path: "new name.txt", originalPath: "old name.txt", index: "R", worktree: "."),
            .init(kind: .changed, path: "readme.txt", index: ".", worktree: "M"),
            .init(kind: .changed, path: "staged.txt", index: "A", worktree: "."),
            .init(kind: .untracked, path: "notes/todo.txt", index: "?", worktree: "?"),
        ])
        XCTAssertEqual(status.shortLines, ["## main...origin/main", "R  old name.txt -> new name.txt", " M readme.txt",
                                           "A  staged.txt", "?? notes/todo.txt"])
    }

    func testACloneWithItsOwnCommitAndAMovedUpstreamIsAheadAndBehind() throws {
        let clone = try makeClone()
        let other = try makeClone(named: "other")
        try commit("theirs\n", to: "theirs.txt", in: other)
        _ = try git(["push", "-q", "origin", "main"], in: other)
        try commit("mine\n", to: "mine.txt", in: clone)
        try commit("more\n", to: "more.txt", in: clone)
        _ = try git(["fetch", "-q"], in: clone)

        let status = try GitStatus.read(try XCTUnwrap(try Git.repository(holding: clone)), base: nil)
        XCTAssertEqual(status.ahead, 2)
        XCTAssertEqual(status.behind, 1)
        XCTAssertEqual(status.shortLines, ["## main...origin/main [ahead 2, behind 1]"])
    }

    func testABranchWithNoUpstreamHasNoUpstreamAheadOrBehind() throws {
        let clone = try makeClone()
        _ = try git(["switch", "-q", "-c", "feature"], in: clone)
        let status = try GitStatus.read(try XCTUnwrap(try Git.repository(holding: clone)), base: nil)
        XCTAssertEqual(status.branch, "feature")
        XCTAssertNil(status.upstream)
        XCTAssertNil(status.ahead)
        XCTAssertNil(status.behind)
        XCTAssertEqual(status.shortLines, ["## feature"])
    }

    func testAFolderInNoRepositoryHasNoGit() throws {
        let folder = root.appendingPathComponent("plain").path
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        XCTAssertNil(try Git.repository(holding: folder))
        let clone = try makeClone()
        XCTAssertNil(try Git.repository(holding: clone + "/.git"), "the .git folder is in no work tree")
    }

    func testAPatchKeepsTheBytesOfATextFileThatIsNotUTF8() throws {
        let clone = try makeClone()
        let latin1 = Data([0x63, 0x61, 0x66, 0xE9, 0x0A])
        try latin1.write(to: URL(fileURLWithPath: clone + "/menu.txt"))
        let repository = try XCTUnwrap(try Git.repository(holding: clone))
        let changes = try GitChanges.read(repository, base: nil, session: "game/ship")
        XCTAssertNotNil(changes.patch.range(of: Data([0x2B]) + latin1), "the added line keeps the byte 0xE9: \(changes.patch as NSData)")
    }

    func testARepositoryWithNoCommitAndADetachedHeadSayWhereTheyAre() throws {
        let empty = root.appendingPathComponent("empty").path
        _ = try git(["init", "-q", "-b", "main", empty], in: root.path)
        XCTAssertEqual(try GitStatus.read(try XCTUnwrap(try Git.repository(holding: empty)), base: nil).shortLines,
                       ["## No commits yet on main"])
        let clone = try makeClone()
        _ = try git(["switch", "-q", "--detach"], in: clone)
        let detached = try GitStatus.read(try XCTUnwrap(try Git.repository(holding: clone)), base: nil)
        XCTAssertNil(detached.branch)
        XCTAssertEqual(detached.shortLines, ["## HEAD (no branch)"])
    }

    func testTheBaseIsTheMergeBaseWithTheDefaultBranchUnlessTheTopicRecordedOne() throws {
        let clone = try makeClone()
        let start = try git(["rev-parse", "HEAD"], in: clone)
        _ = try git(["switch", "-q", "-c", "feature"], in: clone)
        try commit("feature\n", to: "feature.txt", in: clone)
        let repository = try XCTUnwrap(try Git.repository(holding: clone))
        XCTAssertEqual(try repository.base(recorded: nil), start, "the merge base with origin/HEAD")
        let other = try git(["rev-parse", "HEAD"], in: clone)
        XCTAssertEqual(try repository.base(recorded: other), other, "a recorded base that the repository has")
        XCTAssertEqual(try repository.base(recorded: String(repeating: "1", count: 40)), start,
                       "a recorded base that the repository no longer has falls back to the merge base")
        _ = try git(["switch", "-q", "--orphan", "fresh"], in: clone)
        XCTAssertNil(try repository.base(recorded: nil), "an unborn branch has no base")
        XCTAssertEqual(try GitStatus.read(repository, base: nil).shortLines.first, "## No commits yet on fresh")

        let local = root.appendingPathComponent("local").path
        _ = try git(["init", "-q", "-b", "master", local], in: root.path)
        try commit("one\n", to: "one.txt", in: local)
        let first = try git(["rev-parse", "HEAD"], in: local)
        _ = try git(["switch", "-q", "-c", "topic"], in: local)
        try commit("two\n", to: "two.txt", in: local)
        XCTAssertEqual(try XCTUnwrap(try Git.repository(holding: local)).base(recorded: nil), first, "the merge base with a local master")
    }

    func testChangesSinceTheBaseHoldCommitsWorkAndUntrackedFilesAndLeaveTheIndexAlone() throws {
        let clone = try makeClone()
        _ = try git(["switch", "-q", "-c", "feature"], in: clone)
        try commit("feature\n", to: "feature.txt", in: clone)
        try write("changed\n", to: clone + "/readme.txt")
        try write("new\nfile\n", to: clone + "/new.txt")
        try write("skip\n", to: clone + "/build.log")
        try write("*.log\n", to: clone + "/.git/info/exclude")
        // git status refreshes the index, so the bytes are read after it.
        let before = try git(["status", "--porcelain"], in: clone)
        let index = try Data(contentsOf: URL(fileURLWithPath: clone + "/.git/index"))

        let repository = try XCTUnwrap(try Git.repository(holding: clone))
        let changes = try GitChanges.read(repository, base: try repository.base(recorded: nil), session: "game/ship")
        XCTAssertEqual(changes.files, [.init(path: "feature.txt", added: 1, deleted: 0), .init(path: "new.txt", added: 2, deleted: 0),
                                       .init(path: "readme.txt", added: 1, deleted: 1)])
        let headers = String(decoding: changes.patch, as: UTF8.self).split(separator: "\n").filter { $0.hasPrefix("diff --git") }
        XCTAssertEqual(headers, ["diff --git a/game/ship/feature.txt b/game/ship/feature.txt", "diff --git a/game/ship/new.txt b/game/ship/new.txt",
                                 "diff --git a/game/ship/readme.txt b/game/ship/readme.txt"])
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: clone + "/.git/index")), index, "the user's index did not change")
        XCTAssertEqual(try git(["status", "--porcelain"], in: clone), before)
    }

    // MARK: - Fixtures

    /// A clone of a bare origin with one commit on main: readme.txt and "old name.txt".
    private func makeClone(named name: String = "clone") throws -> String {
        let origin = root.appendingPathComponent("origin.git").path
        if !FileManager.default.fileExists(atPath: origin) {
            let seed = root.appendingPathComponent("seed").path
            _ = try git(["init", "-q", "-b", "main", seed], in: root.path)
            try write("readme\n", to: seed + "/readme.txt")
            try write("old\n", to: seed + "/old name.txt")
            _ = try git(["add", "."], in: seed)
            _ = try git(["commit", "-q", "-m", "first"], in: seed)
            _ = try git(["clone", "-q", "--bare", seed, origin], in: root.path)
        }
        let clone = root.appendingPathComponent(name).path
        _ = try git(["clone", "-q", origin, clone], in: root.path)
        return clone
    }

    private func commit(_ text: String, to file: String, in repository: String) throws {
        try write(text, to: repository + "/" + file)
        _ = try git(["add", file], in: repository)
        _ = try git(["commit", "-q", "-m", file], in: repository)
    }

    private func write(_ text: String, to path: String) throws {
        try Data(text.utf8).write(to: URL(fileURLWithPath: path))
    }

    @discardableResult
    private func git(_ arguments: [String], in directory: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "user.name=Test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgSign=false"] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CLIError("git \(arguments.joined(separator: " ")): \(text)") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
