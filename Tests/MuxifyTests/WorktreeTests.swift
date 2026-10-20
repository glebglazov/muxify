import XCTest
@testable import MuxifyCore

final class WorktreeTests: XCTestCase {
    private func config(_ text: String) throws -> Config {
        try Config.load(path: "/cfg/muxify/config.yaml") { _ in text }.get()
    }

    func testConfigHasNoWorktreeDirectoryAndReportsTheRemovedKeysAsUnknown() throws {
        XCTAssertEqual(try config("").topics, Config.Topics())
        let removed = try config("topics:\n  worktree: true\n  worktree_dir: /trees")
        XCTAssertEqual(removed.problems, [ConfigProblem(path: "/cfg/muxify/config.yaml", line: 2, message: "unknown key \"topics.worktree\""),
                                          ConfigProblem(path: "/cfg/muxify/config.yaml", line: 3, message: "unknown key \"topics.worktree_dir\"")])
        XCTAssertFalse(Config.template.contains("worktree_dir"))
        XCTAssertFalse(Config.template.contains("#   worktree: false"))
        XCTAssertEqual(try config("topics: []").problems.count, 1)
        XCTAssertEqual(try config("topics: {other: true}").problems.count, 1)
    }

    func testNewWorktreesGoToTheWorktreesFolderBesideTheTopicRecords() {
        func paths(_ environment: [String: String]) -> MuxifyPaths { MuxifyPaths(environment: environment, home: "/Users/me") }
        XCTAssertEqual(paths(["XDG_STATE_HOME": "/xdg state"]).worktrees.path, "/xdg state/muxify/worktrees")
        XCTAssertEqual(paths(["XDG_STATE_HOME": "/xdg state"]).topics.path, "/xdg state/muxify/topics")
        XCTAssertEqual(paths(["XDG_STATE_HOME": "/xdg state"]).zenFile.path, "/xdg state/muxify/zen.json")
        XCTAssertEqual(paths([:]).worktrees.path, "/Users/me/.local/state/muxify/worktrees")
        XCTAssertEqual(paths(["XDG_STATE_HOME": ""]).worktrees.path, "/Users/me/.local/state/muxify/worktrees", "an empty value is unset")
    }

    func testPlanMakesTheWorktreeFromTheBaseApartFromTheTmuxCommandsAndRecordsItAsCreated() throws {
        var project = Project(path: "/work/game source", name: "team/game")
        project.alias = "My Game"
        project.layout = .plainRepository([Worktree(path: "/work/game source", branch: "main")])
        let plan = try TopicProjectPlan(topic: TopicRecord(id: "topic", title: "Fix links", slug: "fix-links"), project: project,
                                        workingCopy: .newWorktree(at: "c0ffee", root: "/work trees"), windows: [], projects: [project]).edit
        let worktree = TopicPlan.WorktreeSpec(projectPath: project.folder.path, path: "/work trees/team/game/fix-links", branch: "fix-links")
        XCTAssertEqual(worktree.arguments, ["worktree", "add", "-b", "fix-links", "/work trees/team/game/fix-links"])
        XCTAssertEqual(plan.newWorktree, TopicPlan.NewWorktree(worktree: worktree, commit: "c0ffee"))
        XCTAssertEqual(plan.commands, [
            .tmux(["new-session", "-d", "-s", "team/game/fix-links", "-c", worktree.path]),
            .tmux(["set-option", "-t", "=team/game/fix-links:", "@muxify_topic", "topic"]),
        ])
        var record = try XCTUnwrap(plan.record)
        record.title = "New title"
        record.slug = "new-title"
        let decoded = try JSONDecoder().decode(TopicRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded.sessions, [.object([
            "project_path": .string(project.folder.path),
            "worktree_path": .string(worktree.path),
            "branch": .string("fix-links"),
            "worktree_created": .bool(true),
            "base": .string("c0ffee"),
        ])])
    }

    func testNewWorktreeOfABareRepositoryGoesToTheWorktreesFolderAsForAPlainOne() throws {
        var project = Project(path: "/work/game_server", name: "game_server")
        let release = Worktree(path: "/work/game_server/release", branch: "release-line")
        project.layout = .bareRepository([release])
        let plan = try TopicProjectPlan(topic: TopicRecord(id: "topic", title: "Fix links", slug: "fix-links"), project: project,
                                        workingCopy: .newWorktree(at: "c0ffee", root: "/state/muxify/worktrees"), windows: [], projects: [project]).edit
        let path = "/state/muxify/worktrees/game_server/fix-links"
        XCTAssertEqual(plan.newWorktree, TopicPlan.NewWorktree(worktree: .init(projectPath: project.folder.path, path: path, branch: "fix-links"), commit: "c0ffee"))
        XCTAssertEqual(plan.commands.first, .tmux(["new-session", "-d", "-s", "game_server/fix-links", "-c", path]))
    }

    func testShellRunsInRequestedDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try Shell.run("/bin/pwd", [], directory: directory.path)
        XCTAssertEqual(URL(fileURLWithPath: result.trimmingCharacters(in: .whitespacesAndNewlines)).resolvingSymlinksInPath(),
                       directory.resolvingSymlinksInPath())
    }

    private func model(head: String?, pointer: String = "gitdir: /repo/.git/worktrees/fix\n",
                       sessionPath: String = "/trees/fix/src", remembered: Bool = true, topicID: String? = "topic") -> TopicsModel {
        var record = TopicRecord(id: "topic", title: "Fix", homeProject: "/repo")
        if remembered {
            record.sessions = [.object(["project_path": .string("/repo"), "worktree_path": .string("/trees/fix"),
                                        "branch": .string("original")])]
        }
        var files = ["/trees/fix/.git": pointer]
        files["/repo/.git/worktrees/fix/HEAD"] = head
        let branches = TopicBranches(records: [record]) { files[$0] }
        let window = TmuxWindow(id: "@1", sessionID: "$1", sessionName: "renamed", index: 0,
                                name: "shell", paneTitle: "", path: "/elsewhere", command: "zsh", isActive: true,
                                paneCount: 1, hasBell: false, sessionActivity: 0, agent: "", storedBrowser: StoredBrowser(),
                                openRequests: [], topicID: topicID, sessionPath: sessionPath)
        return TopicsModel(records: [record], windows: [window], config: Config(), selection: TopicSelection(), branches: branches)
    }

    func testBranchBadgeReadsHeadNamesAndRelativeGitdir() {
        // The Worktree folder is "fix", so the badge shows only a branch the folder does not name.
        for (branch, badge) in [("fix", nil), ("feature/long-branch-name", "feature/long-branch-name"), ("another-branch", "another-branch")] {
            let rows = model(head: "ref: refs/heads/\(branch)\n").rows
            XCTAssertEqual(rows.first?.sessions.first?.branch, badge)
            XCTAssertEqual(rows.first?.sessions.first?.projectName, "repo/fix")
            XCTAssertEqual(rows.first?.sessions.first?.isHome, true)
        }
        XCTAssertEqual(model(head: "ref: refs/heads/feature/fix\n", pointer: "gitdir: ../../repo/.git/worktrees/fix\n")
            .rows.first?.sessions.first?.branch, "feature/fix")
    }

    func testBranchBadgeIsAbsentForDetachedMissingMalformedAndNormalSessions() {
        for head in [nil, "", "123456789abcdef\n", "ref: refs/tags/v1\n", "ref: refs/heads/\n",
                     "ref: refs/heads/fix\nref: refs/heads/other", "ref: refs/heads/bad name"] {
            XCTAssertNil(model(head: head).rows.first?.sessions.first?.branch, head ?? "missing")
        }
        for pointer in ["", "gitdir: ", "garbage", "gitdir: /missing", "gitdir: /repo\nother"] {
            XCTAssertNil(model(head: "ref: refs/heads/feature/fix", pointer: pointer).rows.first?.sessions.first?.branch)
        }
        XCTAssertNil(model(head: "ref: refs/heads/feature/fix", remembered: false).rows.first?.sessions.first?.branch)
        XCTAssertNil(model(head: "ref: refs/heads/feature/fix", sessionPath: "/repo").rows.first?.sessions.first?.branch)
        XCTAssertNil(model(head: "ref: refs/heads/feature/fix", sessionPath: "/trees/fix-other").rows.first?.sessions.first?.branch)
        XCTAssertNil(model(head: "ref: refs/heads/feature/fix", topicID: nil).rows.last?.sessions.first?.branch)
    }

    func testGitFailureNamesGit() {
        XCTAssertThrowsError(try Shell.run("/usr/bin/git", ["not-a-command"])) { error in
            XCTAssertTrue(String(describing: error).hasPrefix("git exited with "))
        }
    }
}
