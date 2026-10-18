import XCTest
@testable import MuxifyCore

final class ProjectAliasTests: XCTestCase {
    private let vault = Project(path: "/work/vault", name: "vault", alias: "My Obsidian")
    private let game = Project(path: "/work/game", name: "game", alias: "Game Server",
                               layout: .bareRepository([Worktree(path: "/work/game/main", branch: "main")]))

    private func window(_ id: String, session: String, directory: String, topic: String? = nil) -> TmuxWindow {
        TmuxWindow(id: id, sessionID: "$" + session, sessionName: session, index: 0, name: "shell", paneTitle: "", path: directory,
                   command: "zsh", isActive: true, paneCount: 1, hasBell: false, sessionActivity: 0, agent: "",
                   storedBrowser: StoredBrowser(), openRequests: [], topicID: topic, sessionPath: directory)
    }

    private func catalog(records: [TopicRecord] = [], windows: [TmuxWindow] = [], mode: SidebarMode = .topics) -> PaletteCatalog {
        var config = Config()
        config.projects = [vault, game]
        let model = TopicsModel(records: records, windows: windows, config: config, selection: TopicSelection(), mode: mode, agents: [], now: Date())
        return PaletteCatalog(windows: windows, agents: [], projects: [vault, game], topics: model, records: records)
    }

    private func discovered(_ config: Config) -> [Project] {
        ProjectDiscovery.discover(config.projectRoots, aliases: config.projectAliases)
    }

    func testConfigGivesAProjectItsAliasByFullPathRelativePathOrHomePath() throws {
        let root = try TestDirectory()
        for name in ["alpha", "beta", "gamma"] {
            try FileManager.default.createDirectory(at: root.url.appendingPathComponent("work/" + name), withIntermediateDirectories: true)
        }
        let text = """
        projects:
          aliases:
            - \(root.url.path)/work/alpha/: My Alpha
            - work/beta: Beta Notes
            - /no/such/project: Nobody
            - ~/Library: Home Library
          paths:
            - path: work/*
            - path: ~/Library
        """
        let config = try Config.load(path: root.url.appendingPathComponent("config.yaml").path) { _ in text }.get()
        XCTAssertEqual(config.problems, [], "an alias of a path that is no Project is not a problem")
        let projects = discovered(config)
        XCTAssertEqual(projects.map(\.name), ["alpha", "beta", "gamma", "Library"], "the alias does not rename the Project")
        XCTAssertEqual(projects.map(\.displayName), ["My Alpha", "Beta Notes", "gamma", "Home Library"])
        XCTAssertTrue(Config.template.contains("#   aliases:"))
    }

    func testConfigReportsAliasEntriesItCannotApply() throws {
        let cases: [(String, String)] = [
            ("{/tmp: x}", "projects.aliases: expected a list"),
            ("[wrong]", "projects.aliases: expected one Project path mapped to its alias"),
            ("[{/tmp: x, /var: y}]", "projects.aliases: expected one Project path mapped to its alias"),
            ("[{}]", "projects.aliases: expected one Project path mapped to its alias"),
            ("[{42: x}]", "projects.aliases: expected a Project path"),
            ("[{/tmp: ''}]", "projects.aliases./tmp: expected a nonempty one-line alias"),
            ("[{/tmp: '  '}]", "projects.aliases./tmp: expected a nonempty one-line alias"),
            ("[{/tmp: 42}]", "projects.aliases./tmp: expected a nonempty one-line alias"),
            ("[{/tmp: null}]", "projects.aliases./tmp: expected a nonempty one-line alias"),
            ("[{/tmp: [x]}]", "projects.aliases./tmp: expected a nonempty one-line alias"),
            ("[{/tmp: \"a\\nb\"}]", "projects.aliases./tmp: expected a nonempty one-line alias"),
        ]
        for (aliases, message) in cases {
            let config = try Config.load(path: "/cfg/config.yaml") { _ in "projects:\n  paths: [{path: /tmp}]\n  aliases: " + aliases }.get()
            XCTAssertEqual(config.problems.map(\.message), [message], aliases)
            XCTAssertEqual(config.problems.first?.line, 3, aliases)
            XCTAssertEqual(discovered(config).map(\.displayName), ["tmp"], aliases)
        }
        let twice = try Config.load(path: "/cfg/config.yaml") { _ in
            "projects:\n  paths: [{path: /tmp}]\n  aliases:\n    - /tmp: First\n    - /tmp/: Second"
        }.get()
        XCTAssertEqual(twice.problems.map(\.message), ["projects.aliases: /tmp/ already has an alias"])
        XCTAssertEqual(discovered(twice).map(\.displayName), ["First"], "the first alias in the file stays")
    }

    func testThePaletteShowsTheAliasFindsTheRowByAliasOrFolderAndOpensASessionNamedAfterTheFolder() {
        let catalog = catalog()
        func titles(_ query: String) -> [String] { catalog.list([.topics, .sessions], query: query).rows.map(\.title.text) }
        XCTAssertEqual(titles("obsidian"), ["My Obsidian"])
        XCTAssertEqual(titles("my obs"), ["My Obsidian"])
        XCTAssertEqual(titles("vault"), ["My Obsidian"], "typing the folder name finds the aliased row")
        XCTAssertEqual(titles("game/main"), ["Game Server/main"])
        let row = catalog.list([.sessions], query: "obsidian").rows[0]
        XCTAssertEqual(row.pick.payload?.ref, .project(OpenDirectory(directory: .local("/work/vault"), name: "vault", reach: .noTopicOnly)))
        let sessions = self.catalog(mode: .sessions).list([.sessions], query: "").rows
        XCTAssertEqual(sessions.map(\.title.text), ["My Obsidian", "Game Server/main"])
        XCTAssertEqual(sessions[1].pick.payload?.ref, .project(OpenDirectory(directory: .local("/work/game/main"), name: "game/main", reach: .anySession)))
    }

    func testProjectListsShowTheAliasAndFindTheRowByAliasOrFolder() {
        let rows = ProjectRows.build(projects: [vault, game], windows: [], records: [], titles: [:])
        func titles(_ query: String) -> [String] { ProjectRows.list(rows, query: query, visits: VisitLog()).rows.map(\.title.text) }
        XCTAssertEqual(titles(""), ["My Obsidian", "Game Server/main"])
        XCTAssertEqual(titles("obsidian"), ["My Obsidian"])
        XCTAssertEqual(titles("vault"), ["My Obsidian"])
    }

    func testSidebarLabelsASessionWithTheAliasAndItsSessionKeepsTheFolderName() throws {
        var record = TopicRecord(id: "t", title: "Write", homeProject: "/work/vault")
        record.sessions = [.object(["project_path": .string("/work/game"), "worktree_path": .string("/work/game/main")])]
        var windows = [window("@1", session: "vault/write", directory: "/work/vault", topic: "t"),
                       window("@2", session: "game/write", directory: "/work/game/main", topic: "t")]
        // A Topic lists its Sessions oldest first.
        windows[1].sessionCreated = 1
        let model = catalog(records: [record], windows: windows).topics!
        XCTAssertEqual(model.rows.first { $0.id == .topic("t") }?.sessions.map(\.projectName), ["My Obsidian", "Game Server/main"])
        var settled = record
        settled.settledAt = "2026-01-01T00:00:00Z"
        settled.sessions.append(.object(["project_path": .string("/work/vault")]))
        XCTAssertEqual(TopicsModel.settledRow(settled, projects: [vault, game], expanded: []).sessions.map(\.projectName),
                       ["Game Server/main", "My Obsidian"])
        let plan = TopicPlan(title: "Write notes", project: vault, records: [], sessionNames: [], id: "n")
        XCTAssertEqual(plan.sessionName, "vault/write-notes")
    }
}
