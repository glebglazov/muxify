import XCTest
@testable import MuxifyCore

final class PaneLabelTests: XCTestCase {
    private func pane(_ id: String = "%1", active: Bool = false, title: String = "", command: String = "zsh",
                      agent: String = "", path: String = Paths.home + "/work/app") -> TmuxPane {
        TmuxPane(id: id, windowID: "@1", isActive: active, title: title, path: path, command: command,
                 agent: agent, agentStatus: "", unread: false)
    }

    private func window(paneTitle: String, command: String) -> TmuxWindow {
        TmuxWindow(id: "@1", sessionID: "$1", sessionName: "app", index: 2, name: command,
                   paneTitle: paneTitle, path: Paths.home + "/work/app", command: command, isActive: true,
                   paneCount: 2, hasBell: false, sessionActivity: 0, agent: "", storedBrowser: StoredBrowser(),
                   openRequests: [])
    }

    func testTitleComesFirstWithoutItsLeadingGlyph() {
        XCTAssertEqual(pane(title: "✳ Fix reward drop", command: "2.1.289", agent: "claude").label, "Fix reward drop")
    }

    func testAgentKindWhenTheTitleIsEmptyOrOnlyTheHostName() {
        XCTAssertEqual(pane(command: "codex", agent: "codex").label, "codex")
        XCTAssertEqual(pane(title: Tmux.hostName, command: "2.1.289", agent: "claude").label, "claude")
        XCTAssertEqual(pane(title: Tmux.shortHostName, command: "2.1.289", agent: "claude").label, "claude")
    }

    func testCommandWhenNoAgentRuns() {
        XCTAssertEqual(pane(title: Tmux.hostName, command: "vim").label, "vim")
    }

    func testShortPathAtAShellEvenWithAnAgentLeftBehind() {
        XCTAssertEqual(pane(command: "zsh").label, "~/w/app")
        XCTAssertEqual(pane(command: "fish", agent: "claude").label, "~/w/app")
    }

    func testAgentIsLabelledByItsOwnPaneNotByTheActiveVimPane() {
        let panes = [pane("%1", command: "2.1.289", agent: "claude"), pane("%2", active: true, title: "vim", command: "vim")]
        let agents = Agent.list(panes: panes, windows: [window(paneTitle: "vim", command: "vim")])
        XCTAssertEqual(agents.map(\.label), ["claude"])
    }

    func testAgentLabelIsItsPaneTitle() {
        let panes = [pane(title: "✳ Rename the Topic", command: "2.1.289", agent: "claude")]
        let agents = Agent.list(panes: panes, windows: [window(paneTitle: Tmux.hostName, command: "zsh")])
        XCTAssertEqual(agents.map(\.label), ["Rename the Topic"])
    }
}
