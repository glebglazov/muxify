import XCTest
@testable import MuxifyCore

final class TopicLifecycleTests: XCTestCase {
    private let game = Project(path: "/work/game", name: "game")
    private let tools = Project(path: "/work/tools", name: "tools")

    private func window(_ id: String, session: String, directory: String, command: String = "claude") -> TmuxWindow {
        TmuxWindow(id: id, sessionID: session, sessionName: "session-" + session, index: 7,
                   name: "agent", paneTitle: "", path: directory, command: command, isActive: true,
                   paneCount: 3, hasBell: false, sessionActivity: 0, agent: "claude",
                   storedBrowser: StoredBrowser(tabURLs: ["about:blank", "https://example.com"], activeTab: 1, layout: PanelLayout(shown: .both)),
                   openRequests: [], topicID: "topic", sessionPath: directory, activePaneID: "%" + id.dropFirst())
    }

    private func snapshot(_ windows: [TmuxWindow], panes: [TmuxPane] = []) -> TmuxSnapshot {
        TmuxSnapshot(windows: windows, clients: [], panes: panes, lastWindowID: nil, serverRunning: true)
    }

    private var topic: TopicRecord {
        var topic = TopicRecord(id: "topic", title: "Fix reward", slug: "fix-reward", homeProject: game.path)
        topic.sessions = [.object(["project_path": .string(game.path), "worktree_path": .string("/trees/game"), "branch": .string("old-branch")])]
        return topic
    }

    func testSettleDefaultsKeepWorkingAgentsInAnyPaneAndKillOtherSessions() {
        let windows = [window("@1", session: "$1", directory: "/trees/game"),
                       window("@2", session: "$2", directory: tools.path)]
        let panes = [TmuxPane(id: "%99", windowID: "@1", command: "claude", agent: "claude", agentStatus: "working", unread: false),
                     TmuxPane(id: "%2", windowID: "@2", command: "zsh", agent: "claude", agentStatus: "working", unread: false)]
        let live = snapshot(windows, panes: panes)
        let choices = TopicSettleSession.choices(topic: topic, snapshot: live, projects: [game, tools])
        XCTAssertEqual(choices.map(\.disposition), [.keep, .kill])
        let edit = TopicSettlePlan(topic: topic, snapshot: live, projects: [game, tools], choices: [], outcome: "  Delivered  ",
                                   now: Date(timeIntervalSince1970: 0)).edit
        XCTAssertEqual(edit.commands, [.tmux(["set-option", "-u", "-t", "$1", "@muxify_topic"]), .tmux(["kill-session", "-t", "$2"])])
        XCTAssertEqual(edit.record?.settledAt, "1970-01-01T00:00:00Z")
        XCTAssertEqual(edit.record?.outcome, "Delivered")
        XCTAssertEqual(edit.record?.sessions.count, 2)
        XCTAssertEqual(edit.record?.sessions.first?["windows"]?[0]?["pane_count"], .integer(3))
    }

    func testSettleHonoursChoicesAndOnlyRemovesMergedUnusedWorktrees() throws {
        let live = snapshot([window("@1", session: "$1", directory: "/trees/game"), window("@2", session: "$2", directory: tools.path)])
        var choices = TopicSettleSession.choices(topic: topic, snapshot: live, projects: [game, tools], mergedWorktrees: ["/trees/game"])
        choices[0].removeWorktree = true
        choices[1].disposition = .keep
        let merged = TopicSettlePlan(topic: topic, snapshot: live, projects: [game, tools], choices: choices, outcome: "", mergedWorktrees: ["/trees/game"]).edit
        XCTAssertEqual(merged.commands, [.tmux(["kill-session", "-t", "$1"]), .tmux(["set-option", "-u", "-t", "$2", "@muxify_topic"]),
                                         .removeMergedWorktree(.init(projectPath: game.path, path: "/trees/game", branch: "old-branch"))])
        let unmerged = TopicSettlePlan(topic: topic, snapshot: live, projects: [game, tools], choices: choices, outcome: "").edit
        XCTAssertEqual(unmerged.commands.count, 2)
        choices[0].disposition = .keep
        let kept = TopicSettlePlan(topic: topic, snapshot: live, projects: [game, tools], choices: choices, outcome: "", mergedWorktrees: ["/trees/game"]).edit
        XCTAssertEqual(kept.commands.count, 2)
        XCTAssertEqual(kept.commands.first, .tmux(["set-option", "-u", "-t", "$1", "@muxify_topic"]))
    }

    func testSettleLeavesAWorktreeThatALiveSessionOfAnotherTopicUses() {
        let path = "/state/muxify/worktrees/game/fix-reward"
        var settling = topic
        settling.sessions = [.object(["project_path": .string(game.path), "worktree_path": .string(path), "branch": .string("fix-reward"),
                                      "worktree_created": .bool(true)])]
        var other = window("@2", session: "$2", directory: path)
        other.topicID = "other"
        let live = snapshot([window("@1", session: "$1", directory: path), other])
        var choices = TopicSettleSession.choices(topic: settling, snapshot: live, projects: [game], mergedWorktrees: [path])
        XCTAssertEqual(choices.map(\.id), ["$1"])
        choices[0].removeWorktree = true
        let edit = TopicSettlePlan(topic: settling, snapshot: live, projects: [game], choices: choices, outcome: "", mergedWorktrees: [path]).edit
        XCTAssertEqual(edit.commands, [.tmux(["kill-session", "-t", "$1"])], "the other Topic's Session keeps the Worktree")
        let alone = TopicSettlePlan(topic: settling, snapshot: snapshot([window("@1", session: "$1", directory: path)]), projects: [game],
                                    choices: choices, outcome: "", mergedWorktrees: [path]).edit
        XCTAssertEqual(alone.commands.last, .removeMergedWorktree(.init(projectPath: game.path, path: path, branch: "fix-reward")))
    }

    func testDormantSettleKeepsRememberedSessions() {
        let edit = TopicSettlePlan(topic: topic, snapshot: snapshot([]), projects: [game], choices: [], outcome: "Done").edit
        XCTAssertEqual(edit.record?.sessions, topic.sessions)
        XCTAssertNotNil(edit.record?.settledAt)
        XCTAssertTrue(edit.commands.isEmpty)
    }

    private var settledWithAgentsAndTabs: TopicRecord {
        var saved = topic
        saved.settledAt = "2026-10-07T12:00:00Z"
        saved.outcome = "Done"
        let windows: [JSONValue] = AgentKind.allCases.enumerated().map { index, kind in
            .object(["name": .string("window-\(index)"), "directory": .string(index == 0 ? "/trees/game" : game.path),
                     "pane_count": .integer(3), "agent": .string(kind.rawValue), "agent_conversation": .string("conversation-'\(index)"),
                     "browser_tabs": .array([.string("about:blank"), .string("https://example.com")]),
                     "browser_active_tab": .integer(1), "browser_open": .bool(false)])
        }
        saved.sessions = [.object(["project_path": .string(game.path), "worktree_path": .string("/trees/game"),
                                  "branch": .string("old-branch"), "windows": .array(windows)]),
                          .object(["project_path": .string(tools.path), "windows": .array([.object(["name": .string("shell"), "directory": .string(tools.path), "start_command": .string("do-not-run")])])])]
        return saved
    }

    private let slugCollision = TopicRecord(id: "other", title: "Fix reward", slug: "fix-reward", homeProject: "/work/game")

    func testReopenRestoresTwoSessionsAllAgentsTabsAndSlugCollision() throws {
        let saved = settledWithAgentsAndTabs
        let edit = try TopicReopenPlan(topic: saved, records: [saved, slugCollision], windows: [], projects: [game, tools], existingDirectories: []).edit
        XCTAssertEqual(edit.record, saved)
        XCTAssertNil(edit.savedCompletionRecord?.settledAt)
        XCTAssertEqual(edit.savedCompletionRecord?.slug, "fix-reward-2")
        XCTAssertEqual(edit.savedCompletionRecord?.outcome, "Done")
        XCTAssertEqual(edit.savedCompletionRecord?.sessions, saved.sessions)
        XCTAssertEqual(edit.selection, .sessionName("game/fix-reward-2"))
        XCTAssertEqual(edit.commands.first, .restoreWorktree(.init(projectPath: game.path, path: "/trees/game", branch: "old-branch"), base: nil))
        XCTAssertTrue(edit.commands.contains(.reopenSession(name: "game/fix-reward-2", directory: "/trees/game", windowName: "window-0")))
        XCTAssertTrue(edit.commands.contains(.reopenSession(name: "tools/fix-reward-2", directory: tools.path, windowName: "shell")))
        let tmux = edit.commands.compactMap { command -> [String]? in if case .tmux(let args) = command { return args }; return nil }
        XCTAssertEqual(tmux.filter { $0.first == "new-window" }.count, 3)
        XCTAssertTrue(tmux.filter { $0.first == "new-window" }.allSatisfy { $0.contains("-a") && $0.contains("=game/fix-reward-2:$") })
        XCTAssertTrue(tmux.contains(["set-option", "-t", "=game/fix-reward-2:", "@muxify_topic", saved.id]))
        XCTAssertTrue(tmux.contains(["set-option", "-t", "=tools/fix-reward-2:", "@muxify_topic", saved.id]))
        let resume = edit.commands.compactMap { command -> String? in
            if case .sendKeys(_, let keys, true) = command { return keys.last }
            return nil
        }
        XCTAssertEqual(resume, ["claude --resume 'conversation-'\\''0'", "codex resume 'conversation-'\\''1'", "opencode --session 'conversation-'\\''2'", "pi --session 'conversation-'\\''3'"])
        XCTAssertTrue(tmux.contains(StoredBrowser(tabURLs: ["about:blank", "https://example.com"], activeTab: 1).setOptionArgs(windowID: "=game/fix-reward-2:$")))
        XCTAssertFalse(tmux.joined().contains("do-not-run"))
    }

    func testReopenShowsTheBrowserAloneWhenTheTopicRememberedItSo() throws {
        var alone = window("@1", session: "$1", directory: game.path, command: "zsh")
        alone.storedBrowser.layout = PanelLayout(shown: .browser, maximized: .terminal)
        var saved = try XCTUnwrap(TopicRecord(id: "topic", title: "Fix reward", slug: "fix-reward", homeProject: game.path)
            .remembering(snapshot([alone]), projects: [game], order: .oldestFirst))
        saved.settledAt = "2026-10-07T12:00:00Z"
        let edit = try TopicReopenPlan(topic: saved, records: [saved], windows: [], projects: [game], existingDirectories: []).edit
        let tmux = edit.commands.compactMap { command -> [String]? in if case .tmux(let args) = command { return args }; return nil }
        let restored = StoredBrowser(tabURLs: ["about:blank", "https://example.com"], activeTab: 1, layout: PanelLayout(shown: .browser))
        XCTAssertTrue(tmux.contains(restored.setOptionArgs(windowID: "=game/fix-reward:$")), "\(tmux)")
    }

    func testStartFreshCreatesOneShellWindowInEachRememberedSessionWithNoTabsOrAgents() throws {
        let saved = settledWithAgentsAndTabs
        let edit = try TopicReopenPlan(topic: saved, records: [saved, slugCollision], windows: [], projects: [game, tools],
                                       existingDirectories: [], choice: .startFresh).edit
        XCTAssertEqual(edit.commands.first, .restoreWorktree(.init(projectPath: game.path, path: "/trees/game", branch: "old-branch"), base: nil),
                       "a missing Worktree is created again")
        let sessions = edit.commands.filter { if case .reopenSession = $0 { return true }; return false }
        XCTAssertEqual(sessions, [.reopenSession(name: "game/fix-reward-2", directory: "/trees/game", windowName: "shell"),
                                  .reopenSession(name: "tools/fix-reward-2", directory: tools.path, windowName: "shell")])
        let tmux = edit.commands.compactMap { command -> [String]? in if case .tmux(let args) = command { return args }; return nil }
        XCTAssertFalse(tmux.contains { $0.first == "new-window" || $0.first == "respawn-window" }, "\(tmux)")
        XCTAssertFalse(tmux.joined().contains("example.com"), "no Tab comes back")
        XCTAssertFalse(edit.commands.contains { if case .sendKeys = $0 { return true }; return false }, "no Agent starts")
        XCTAssertNil(edit.savedCompletionRecord?.settledAt)
        XCTAssertEqual(edit.selection, .sessionName("game/fix-reward-2"))
    }

    func testReopeningListsOnlyTheAgentsThatCanResume() throws {
        var saved = settledWithAgentsAndTabs
        saved.sessions = [.object(["project_path": .string(game.path), "windows": .array([
            .object(["name": .string("with-id"), "agent": .string("claude"), "agent_conversation": .string("abc")]),
            .object(["name": .string("without-id"), "agent": .string("claude")]),
        ])])]
        let reopening = try TopicReopening(topic: saved, records: [saved], windows: [], projects: [game], existingDirectories: [], choice: .reopen)
        XCTAssertEqual(reopening.sessions[0].windows.map(\.agent), [.init(kind: .claude, conversation: "abc"), nil])
        let resume = try TopicReopenPlan(topic: saved, records: [saved], windows: [], projects: [game], existingDirectories: []).edit.commands
            .filter { if case .sendKeys(_, _, true) = $0 { return true }; return false }
        XCTAssertEqual(resume, [.sendKeys(target: "=game/fix-reward:$", keys: ["claude --resume 'abc'"], literal: true)])
    }

    func testReopenKeepsSessionWorktreeWhenFirstWindowUsesMainWorkingCopy() throws {
        var saved = topic
        saved.sessions = [.object(["project_path": .string(game.path), "worktree_path": .string("/trees/game"),
                                  "branch": .string("old-branch"), "windows": .array([.object(["name": .string("main"), "directory": .string(game.path)])])])]
        let edit = try TopicReopenPlan(topic: saved, records: [saved], windows: [], projects: [game], existingDirectories: ["/trees/game"]).edit
        XCTAssertEqual(edit.commands.first, .reopenSession(name: "game/fix-reward", directory: "/trees/game", windowName: "main"))
        XCTAssertTrue(edit.commands.contains(.tmux(["respawn-window", "-k", "-t", "=game/fix-reward:$", "-c", game.path])))
    }

    func testReopenRestoresACreatedWorktreeAndReusesAPickedOneThatStillExists() throws {
        var saved = topic
        saved.sessions.append(.object(["project_path": .string(tools.path), "worktree_path": .string("/work/tools/main"),
                                       "branch": .string("main"), "worktree_created": .bool(false)]))
        let edit = try TopicReopenPlan(topic: saved, records: [saved], windows: [], projects: [game, tools],
                                       existingDirectories: ["/work/tools/main"]).edit
        let restored = edit.commands.compactMap { command -> String? in if case .restoreWorktree(let spec, _) = command { return spec.path }; return nil }
        XCTAssertEqual(restored, ["/trees/game"])
        XCTAssertTrue(edit.commands.contains(.reopenSession(name: "tools/fix-reward", directory: "/work/tools/main", windowName: "shell")))
        XCTAssertEqual(edit.savedCompletionRecord?.sessions, saved.sessions)
    }

    func testReopenExistingWorktreeAndSessionNameCollisionInSecondProject() throws {
        var saved = topic
        saved.sessions.append(.object(["project_path": .string(tools.path)]))
        var outside = window("@9", session: "$9", directory: tools.path)
        outside.topicID = nil
        let collision = TmuxWindow(id: outside.id, sessionID: outside.sessionID, sessionName: "tools/fix-reward", index: 7,
                                   name: "shell", paneTitle: "", path: tools.path, command: "zsh", isActive: true,
                                   paneCount: 1, hasBell: false, sessionActivity: 0, agent: "", storedBrowser: StoredBrowser(), openRequests: [])
        let edit = try TopicReopenPlan(topic: saved, records: [saved], windows: [collision], projects: [game, tools], existingDirectories: ["/trees/game"]).edit
        XCTAssertEqual(edit.savedCompletionRecord?.slug, "fix-reward-2")
        XCTAssertFalse(edit.commands.contains { if case .restoreWorktree = $0 { return true }; return false })
        XCTAssertThrowsError(try TopicReopenPlan(topic: saved, records: [saved], windows: [window("@1", session: "$1", directory: game.path)], projects: [game, tools], existingDirectories: []))
    }
}

private extension JSONValue {
    subscript(index: Int) -> JSONValue? {
        if case .array(let values) = self, values.indices.contains(index) { return values[index] }
        return nil
    }
}

extension TopicEdit {
    var savedCompletionRecord: TopicRecord? {
        if case .save(let record) = completion { return record }
        return nil
    }
}
