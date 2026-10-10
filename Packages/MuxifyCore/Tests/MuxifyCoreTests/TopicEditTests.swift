import XCTest
@testable import MuxifyCore

final class TopicEditTests: XCTestCase {
    private let game = Project(path: "/work/game", name: "game")
    private let tools = Project(path: "/work/tools", name: "tools")
    private let topic = TopicRecord(id: "topic", title: "Fix", slug: "fix", homeProject: "/work/game")

    private func window(_ id: String = "@1", session: String = "$1", name: String = "game/fix",
                        topicID: String? = "topic", directory: String = "/work/game",
                        panes: Int = 1, active: Bool = true) -> TmuxWindow {
        TmuxWindow(id: id, sessionID: session, sessionName: name, index: 4,
                   name: "agent", paneTitle: "", path: directory, command: "claude", isActive: active,
                   paneCount: panes, hasBell: false, sessionActivity: 0, agent: "claude",
                   storedBrowser: StoredBrowser(tabURLs: ["https://example.com"], layout: PanelLayout(shown: .both)),
                   openRequests: [], topicID: topicID, sessionPath: directory)
    }

    func testRenameChangesEachSessionOnceAndKeepsRecordIdentityAndUnknownFields() throws {
        var record = topic
        record.sessions = [.object(["project_path": .string(game.path), "future": .bool(true)])]
        record.unknownFields = ["future": .array([.integer(42)])]
        record.createdAt = "1970-01-01T00:00:00Z"
        let windows = [
            window(),
            window("@2", active: false),
            window("@3", session: "$2", name: "changed-by-hand", directory: tools.path),
            window("@4", session: "$2", name: "changed-by-hand", directory: tools.path, active: false),
            window("@5", session: "$3", name: "outside", topicID: nil),
        ]
        let edit = try TopicRenamePlan(topic: record, title: "  New title  ", records: [record],
                                       windows: windows, projects: [game, tools]).edit
        var expected = record
        expected.title = "New title"
        expected.slug = "new-title"
        XCTAssertEqual(edit.record, expected)
        XCTAssertEqual(edit.commands, [
            ["rename-session", "-t", "$1", "game/new-title"],
            ["rename-session", "-t", "$2", "tools/new-title"],
        ].map(TopicPlan.Command.tmux))
        XCTAssertEqual(edit.selection, .unchanged)
    }

    func testRenameUntitledUpdatesAllSessionNamesAndKeepsTopicID() throws {
        let record = TopicRecord(id: "untitled", slug: "untitled-7", homeProject: game.path)
        let windows = [
            window(name: "game/untitled-7", topicID: record.id),
            window("@2", session: "$2", name: "tools/untitled-7", topicID: record.id, directory: tools.path),
        ]
        let edit = try TopicRenamePlan(topic: record, title: "Reward drop", records: [record],
                                       windows: windows, projects: [game, tools]).edit
        XCTAssertEqual(edit.record?.id, "untitled")
        XCTAssertEqual(edit.record?.title, "Reward drop")
        XCTAssertEqual(edit.record?.slug, "reward-drop")
        XCTAssertEqual(edit.commands, [
            ["rename-session", "-t", "$1", "game/reward-drop"],
            ["rename-session", "-t", "$2", "tools/reward-drop"],
        ].map(TopicPlan.Command.tmux))
    }

    func testRenameToCurrentTitleDoesNotReserveItsOwnSlugOrSessionNames() throws {
        let edit = try TopicRenamePlan(topic: topic, title: "Fix", records: [topic],
                                       windows: [window()], projects: [game]).edit
        XCTAssertEqual(edit.record, topic)
        XCTAssertEqual(edit.commands, [.tmux(["rename-session", "-t", "$1", "game/fix"])])
    }

    func testRenameCollisionInSecondProjectGivesEverySessionTheSameSuffix() throws {
        let windows = [
            window(),
            window("@2", session: "$2", name: "tools/fix", directory: tools.path),
            window("@3", session: "$3", name: "tools/next", topicID: nil, directory: tools.path),
        ]
        let edit = try TopicRenamePlan(topic: topic, title: "Next", records: [topic],
                                       windows: windows, projects: [game, tools]).edit
        XCTAssertEqual(edit.record?.slug, "next-2")
        XCTAssertEqual(edit.commands, [
            ["rename-session", "-t", "$1", "game/next-2"],
            ["rename-session", "-t", "$2", "tools/next-2"],
        ].map(TopicPlan.Command.tmux))
    }

    func testDormantRenameChecksRememberedProjectsAndStoresBlankTitleAsUntitled() throws {
        var record = topic
        record.sessions = [.object(["project_path": .string(tools.path)])]
        let outside = window("@3", session: "$3", name: "tools/next", topicID: nil, directory: tools.path)
        let named = try TopicRenamePlan(topic: record, title: "Next", records: [record],
                                        windows: [outside], projects: [game, tools]).edit
        XCTAssertEqual(named.record?.slug, "next-2")
        XCTAssertTrue(named.commands.isEmpty)
        let untitled = try TopicRenamePlan(topic: record, title: " \n ", records: [record],
                                           windows: [], projects: [game, tools]).edit
        XCTAssertNil(untitled.record?.title)
        XCTAssertEqual(untitled.record?.slug, "untitled-1")
        XCTAssertEqual(untitled.record?.id, record.id)
        XCTAssertTrue(untitled.commands.isEmpty)
    }

    func testRenameRejectsTwoLiveSessionsInOneProject() {
        XCTAssertThrowsError(try TopicRenamePlan(topic: topic, title: "Next", records: [topic],
                                                  windows: [window(), window("@2", session: "$2", name: "hand-renamed")],
                                                  projects: [game])) { error in
            XCTAssertEqual(String(describing: error), TopicEditFailure.duplicateProject.description)
        }
    }

    func testAddExistingProjectUsesMembershipAndSessionIdentityAfterManualRename() throws {
        let existing = window(name: "changed-by-hand")
        let edit = try TopicProjectPlan(topic: topic, project: game, workingCopy: .homeProject,
                                        windows: [existing, window("@2", name: "changed-by-hand", active: false)],
                                        projects: [game]).edit
        XCTAssertNil(edit.record)
        XCTAssertTrue(edit.commands.isEmpty)
        XCTAssertEqual(edit.selection, .sessionID("$1"))
    }

    func testAddMissingProjectCreatesInProjectDirectoryAndRemembersIt() throws {
        var record = topic
        record.unknownFields = ["future": .string("keep")]
        record.sessions = [.object(["project_path": .string(game.path), "future": .bool(true)])]
        let edit = try TopicProjectPlan(topic: record, project: tools, workingCopy: .homeProject, windows: [window()], projects: [game, tools]).edit
        var expected = record
        expected.sessions.append(.object(["project_path": .string(tools.path)]))
        XCTAssertEqual(edit.record, expected)
        XCTAssertEqual(edit.commands, [
            ["new-session", "-d", "-s", "tools/fix", "-c", "/work/tools"],
            ["set-option", "-t", "=tools/fix:", "@muxify_topic", "topic"],
        ].map(TopicPlan.Command.tmux))
        XCTAssertEqual(edit.selection, .sessionName("tools/fix"))
    }

    func testAddExistingWorktreeProjectRecognizesCanonicalProjectPath() throws {
        var record = topic
        record.sessions = [.object(["project_path": .string(game.path), "worktree_path": .string("/trees/fix"),
                                    "branch": .string("fix")])]
        let existing = window(name: "hand-renamed", directory: "/trees/fix")
        let equivalent = Project(path: "/work/game/./", name: "game")
        let edit = try TopicProjectPlan(topic: record, project: equivalent, workingCopy: .homeProject, windows: [existing], projects: [game]).edit
        XCTAssertNil(edit.record)
        XCTAssertTrue(edit.commands.isEmpty)
        XCTAssertEqual(edit.selection, .sessionID("$1"))
    }

    func testAddDormantProjectReplacesOldWorktreeLocationAndKeepsUnknownSessionFields() throws {
        var record = topic
        record.sessions = [.object(["project_path": .string(game.path), "worktree_path": .string("/trees/fix"),
                                    "branch": .string("fix"), "worktree_created": .bool(true), "base": .string("c0ffee"),
                                    "future": .bool(true)])]
        let edit = try TopicProjectPlan(topic: record, project: game, workingCopy: .homeProject, windows: [], projects: [game]).edit
        XCTAssertEqual(edit.record?.sessions, [.object(["project_path": .string(game.path), "future": .bool(true)])])
        XCTAssertEqual(edit.selection, .sessionName("game/fix"))
    }

    func testAddProjectRejectsConflictingSessionNameAndDuplicateMembership() {
        let outside = window(name: "game/fix", topicID: nil)
        XCTAssertThrowsError(try TopicProjectPlan(topic: topic, project: game, workingCopy: .homeProject, windows: [outside], projects: [game])) { error in
            XCTAssertEqual(String(describing: error), TopicEditFailure.sessionNameInUse.description)
        }
        XCTAssertThrowsError(try TopicProjectPlan(topic: topic, project: game, workingCopy: .homeProject,
                                                   windows: [window(), window("@2", session: "$2", name: "manual")],
                                                   projects: [game])) { error in
            XCTAssertEqual(String(describing: error), TopicEditFailure.duplicateProject.description)
        }
    }

    func testThreePaneExtractionBreaksExactPaneAndSelectsStablePaneIdentity() throws {
        let source = window(panes: 3)
        let edit = try TopicPanePlan(source: TopicPaneSource(paneID: "%7", window: source),
                                     records: [], windows: [source], projects: [game], id: "new",
                                     now: Date(timeIntervalSince1970: 0), clientTTY: "/dev/tty1").edit
        XCTAssertNil(edit.record?.title)
        XCTAssertEqual(edit.record?.id, "new")
        XCTAssertEqual(edit.record?.slug, "untitled-1")
        XCTAssertEqual(edit.record?.homeProject, game.path)
        XCTAssertEqual(edit.record?.createdAt, "1970-01-01T00:00:00Z")
        XCTAssertEqual(edit.record?.order, -1)
        XCTAssertEqual(edit.record?.sessions, [.object(["project_path": .string(game.path)])])
        XCTAssertEqual(edit.commands, [
            .newTopicSession(name: "game/untitled-1", directory: game.path),
            .tmux(["set-option", "-t", "=game/untitled-1:", "@muxify_topic", "new"]),
            .tmux(["switch-client", "-c", "/dev/tty1", "-t", "=game/untitled-1:"]),
            .tmux(["break-pane", "-d", "-s", "%7", "-t", "=game/untitled-1:"]),
            .removeTopicPlaceholder,
        ])
        XCTAssertEqual(edit.selection, .paneID("%7"))
    }

    func testOnePaneExtractionMovesWholeWindowAndDoesNotChangeBrowserOptions() throws {
        let source = window()
        let edit = try TopicPanePlan(source: TopicPaneSource(paneID: "%7", window: source),
                                     records: [], windows: [source], projects: [game], id: "new").edit
        XCTAssertEqual(edit.commands, [
            .newTopicSession(name: "game/untitled-1", directory: game.path),
            .tmux(["set-option", "-t", "=game/untitled-1:", "@muxify_topic", "new"]),
            .tmux(["move-window", "-d", "-s", "$1:@1", "-t", "=game/untitled-1:"]),
            .removeTopicPlaceholder,
        ])
        XCTAssertEqual(edit.selection, .paneID("%7"))
        XCTAssertEqual(source.storedBrowser.tabURLs, ["https://example.com"])
        XCTAssertEqual(source.storedBrowser.layout.shown, .both)
    }

    func testExplicitHomeProjectChangesUntitledSessionWithoutChangingPaneSource() throws {
        let source = window(panes: 3)
        let edit = try TopicPanePlan(source: TopicPaneSource(paneID: "%7", window: source), project: tools,
                                     records: [], windows: [source], projects: [game, tools], id: "new").edit
        XCTAssertEqual(edit.record?.homeProject, tools.path)
        XCTAssertEqual(edit.commands.first, .newTopicSession(name: "tools/untitled-1", directory: tools.path))
        XCTAssertTrue(edit.commands.contains(.tmux(["break-pane", "-d", "-s", "%7", "-t", "=tools/untitled-1:"])))
        XCTAssertEqual(edit.selection, .paneID("%7"))
    }

    func testExtractionUsesWorktreeProjectAndUntitledNumberFromOpenTopicsAndSessions() throws {
        var record = topic
        record.sessions = [.object(["project_path": .string(game.path), "worktree_path": .string("/trees/fix")])]
        let source = window(directory: "/trees/fix", panes: 3)
        let other = TopicRecord(id: "other", slug: "untitled-1")
        let occupied = window("@2", session: "$2", name: "game/untitled-2", topicID: nil)
        let edit = try TopicPanePlan(source: TopicPaneSource(paneID: "%7", window: source),
                                     records: [record, other], windows: [source, occupied], projects: [game], id: "new").edit
        XCTAssertEqual(edit.record?.slug, "untitled-3")
        XCTAssertEqual(edit.record?.homeProject, game.path)
        XCTAssertEqual(edit.commands.first, .newTopicSession(name: "game/untitled-3", directory: game.path))
        XCTAssertEqual(edit.selection, .paneID("%7"))
    }

    func testPaneIdentityRejectsMissingOrChangedSourcesBeforePlanning() throws {
        let source = window(panes: 3)
        let pane = TmuxPane(id: "%7", windowID: "@1", command: "claude", agent: "claude", agentStatus: "working", unread: false)
        let snapshot = TmuxSnapshot(windows: [source], clients: [], panes: [pane], lastWindowID: nil, serverRunning: true)
        let identity = try TopicPaneIdentity(output: "%7 @1 $1 3\n")
        XCTAssertEqual(try identity.source(in: snapshot).paneID, "%7")
        XCTAssertEqual(try identity.source(in: snapshot).window.id, "@1")
        XCTAssertThrowsError(try identity.source(in: TmuxSnapshot(windows: [source], clients: [], panes: [],
                                                                  lastWindowID: nil, serverRunning: true)))
        XCTAssertThrowsError(try TopicPaneIdentity(output: "%7 @1 $1 1").source(in: snapshot))
        XCTAssertThrowsError(try TopicPaneIdentity(output: "%7 @1 $2 3").source(in: snapshot))
        XCTAssertThrowsError(try TopicPaneIdentity(output: "%7 @1 $1 0"))
        XCTAssertThrowsError(try TopicPaneIdentity(output: "unexpected"))
        XCTAssertThrowsError(try TopicPanePlan(source: TopicPaneSource(paneID: "%7", window: source),
                                               records: [], windows: [], projects: [game]))
    }

    func testPlansRejectProjectNamesThatTmuxCannotUse() {
        let invalid = Project(path: game.path, name: "bad.name")
        XCTAssertThrowsError(try TopicProjectPlan(topic: topic, project: invalid, workingCopy: .homeProject, windows: [], projects: [invalid]))
        XCTAssertThrowsError(try TopicRenamePlan(topic: topic, title: "Next", records: [topic],
                                                  windows: [window()], projects: [invalid]))
        let source = window()
        XCTAssertThrowsError(try TopicPanePlan(source: TopicPaneSource(paneID: "%7", window: source),
                                               records: [], windows: [source], projects: [invalid]))
    }
}
