import XCTest
@testable import MuxifyCore

final class TopicMembershipTests: XCTestCase {
    private let project = Project(path: "/work/game", name: "game")
    private let topic = TopicRecord(id: "topic", title: "Fix", slug: "fix", homeProject: "/work/game")

    private func window(_ id: String = "@1", session: String = "$1", topic: String? = nil,
                        path: String = "/work/game", directory: String = "/work/game") -> TmuxWindow {
        TmuxWindow(id: id, sessionID: session, sessionName: "session-" + session, index: 0,
                   name: "agent", paneTitle: "", path: path, command: "claude", isActive: true,
                   paneCount: 2, hasBell: false, sessionActivity: 0, agent: "claude",
                   storedBrowser: StoredBrowser(tabURLs: ["https://example.com"], layout: PanelLayout(shown: .both)),
                   openRequests: [], topicID: topic, sessionPath: directory)
    }

    func testMenuSourceResolvesCurrentMembershipAfterAWindowMoves() throws {
        let previous = window()
        let current = window(session: "$2", topic: "first")
        let source = try TopicMembershipPlan.Source.window(previous).resolved(in: [current])
        let plan = try TopicMembershipPlan(source: source, destination: topic, records: [topic],
                                           windows: [current], projects: [project])
        XCTAssertTrue(plan.commands.contains(.tmux(["move-window", "-d", "-s", "$2:@1", "-t", "=game/fix:"])))
        XCTAssertThrowsError(try TopicMembershipPlan.Source.window(previous).resolved(in: []))
        XCTAssertThrowsError(try TopicMembershipPlan.Source.session(previous).resolved(in: [current]))
    }

    func testMoveWindowToExistingProjectSessionPreservesWindowIdentity() throws {
        let source = window()
        let destination = window("@2", session: "$2", topic: topic.id)
        let plan = try TopicMembershipPlan(source: .window(source), destination: topic, records: [topic],
                                           windows: [source, destination], projects: [project], clientTTY: "/dev/tty1")
        XCTAssertEqual(plan.commands, [
            ["switch-client", "-c", "/dev/tty1", "-t", "$2:"],
            ["move-window", "-d", "-s", "$1:@1", "-t", "$2:"],
            ["switch-client", "-c", "/dev/tty1", "-t", "$2:@1"],
        ].map(TopicPlan.Command.tmux))
        XCTAssertEqual(plan.record, topic)
    }

    func testMoveWindowMakesMissingSessionAndRemovesPlaceholder() throws {
        let source = window()
        let plan = try TopicMembershipPlan(source: .window(source), destination: topic, records: [topic],
                                           windows: [source], projects: [project])
        XCTAssertEqual(plan.commands, [
            .newTopicSession(name: "game/fix", directory: "/work/game"),
            .tmux(["set-option", "-t", "=game/fix:", "@muxify_topic", "topic"]),
            .tmux(["move-window", "-d", "-s", "$1:@1", "-t", "=game/fix:"]),
            .removeTopicPlaceholder,
        ])
        XCTAssertEqual(plan.record?.sessions, [.object(["project_path": .string(project.folder.path)])])
    }

    func testNewTopicFromSessionLinksAndRenamesWithoutChangingWindows() throws {
        let source = window()
        let plan = try TopicMembershipPlan(source: .session(source), title: "Fix", records: [],
                                           windows: [source], projects: [project], id: "new")
        XCTAssertEqual(plan.commands, [
            ["rename-session", "-t", "$1", "game/fix"],
            ["set-option", "-t", "$1", "@muxify_topic", "new"],
        ].map(TopicPlan.Command.tmux))
        XCTAssertEqual(plan.record?.homeProject, project.folder.path)
        XCTAssertEqual(plan.record?.title, "Fix")
    }

    func testNewTopicFromWindowUsesUntitledNaming() throws {
        let source = window()
        let plan = try TopicMembershipPlan(source: .window(source), title: " \n ", records: [],
                                           windows: [source], projects: [project], id: "new")
        XCTAssertNil(plan.record?.title)
        XCTAssertEqual(plan.record?.slug, "untitled-1")
        XCTAssertTrue(plan.commands.contains(.tmux(["move-window", "-d", "-s", "$1:@1", "-t", "=game/untitled-1:"])))
    }

    func testRemoveFromTopicUnsetsMembershipAndTheTopicForgetsTheSession() {
        var remembering = topic
        remembering.sessions = [.object(["project_path": .string("/work/game")]), .object(["project_path": .string("/work/tools")])]
        let plan = TopicMembershipPlan(removingSession: window(topic: topic.id), records: [remembering], projects: [project])
        XCTAssertEqual(plan.record?.sessions, [.object(["project_path": .string("/work/tools")])])
        XCTAssertEqual(plan.commands, [.tmux(["set-option", "-u", "-t", "$1", "@muxify_topic"])])
    }

    func testSessionCannotJoinOccupiedProjectAndSameSessionIsNoOp() throws {
        let source = window()
        let existing = window("@2", session: "$2", topic: topic.id)
        XCTAssertThrowsError(try TopicMembershipPlan(source: .session(source), destination: topic,
                                                      records: [topic], windows: [source, existing], projects: [project]))
        let plan = try TopicMembershipPlan(source: .window(existing), destination: topic,
                                           records: [topic], windows: [existing], projects: [project])
        XCTAssertTrue(plan.commands.isEmpty)
        XCTAssertNil(plan.record)
    }

    func testMainWorkingCopyBadgeAndDetachedWorktreeProjectIdentity() throws {
        var record = topic
        record.sessions = [.object(["project_path": .string(project.folder.path), "worktree_path": .string("/trees/fix"),
                                    "branch": .string("fix")])]
        for path in ["/work/game", "/work/game/src"] {
            XCTAssertTrue(TopicsModel.usesMainWorkingCopy(window(path: path, directory: "/trees/fix"),
                                                          record: record, projects: [project]))
        }
        for path in ["/work/games", "/trees/fix", "/trees/fix/src"] {
            XCTAssertFalse(TopicsModel.usesMainWorkingCopy(window(path: path, directory: "/trees/fix"),
                                                           record: record, projects: [project]))
        }
        let detached = window(directory: "/trees/fix")
        let existing = window("@2", session: "$2", topic: "other")
        let other = TopicRecord(id: "other", title: "Other", slug: "other", homeProject: project.folder.path)
        XCTAssertThrowsError(try TopicMembershipPlan(source: .session(detached), destination: other,
                                                      records: [record, other], windows: [detached, existing], projects: [project]))
        let plan = try TopicMembershipPlan(source: .session(detached), title: "Moved", records: [record],
                                           windows: [detached], projects: [project], id: "new")
        XCTAssertEqual(plan.record?.homeProject, project.folder.path)
        XCTAssertEqual(plan.record?.sessions.first?["worktree_path"]?.string, "/trees/fix")
    }
}
