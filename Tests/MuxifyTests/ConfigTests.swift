import XCTest

final class ConfigTests: XCTestCase {
    private let root = "/cfg/muxify/config.yaml"

    private func load(_ files: [String: String]) throws -> Config {
        try Config.load(path: root) { files[$0] }.get()
    }

    private func load(_ text: String) throws -> Config {
        try load([root: text])
    }

    private func trigger(_ string: String) -> KeyTrigger {
        try! KeyTrigger(string)
    }

    func testMissingOrEmptyFileGivesTheDefaults() throws {
        for config in [try load([:]), try load(""), try load("# nothing here\n\n")] {
            XCTAssertEqual(config.keybinds.action(for: trigger("cmd+s")), .toggleSidebar)
            XCTAssertEqual(config.keybinds.action(for: trigger("ctrl+cmd+s")), .toggleSidebar)
            XCTAssertEqual(config.keybinds.action(for: trigger("cmd+b")), .toggleBrowser)
            XCTAssertEqual(config.keybinds.firstTrigger(for: .toggleSidebar), trigger("cmd+s"))
            XCTAssertNil(config.ghosttyConfigFile)
            XCTAssertEqual(config.problems, [])
        }
    }

    func testNamingAnActionReplacesItsDefaults() throws {
        let config = try load("""
        keybindings:
          toggle_sidebar: ctrl+cmd+s
        """)
        XCTAssertNil(config.keybinds.action(for: trigger("cmd+s")))
        XCTAssertEqual(config.keybinds.action(for: trigger("ctrl+cmd+s")), .toggleSidebar)
        XCTAssertEqual(config.keybinds.firstTrigger(for: .toggleSidebar), trigger("ctrl+cmd+s"))
        XCTAssertEqual(config.keybinds.action(for: trigger("cmd+b")), .toggleBrowser)
        XCTAssertEqual(config.problems, [])
    }

    func testAListBindsEveryTriggerAndTheFirstIsShown() throws {
        let config = try load("""
        keybindings:
          toggle_browser: [cmd+e, cmd+shift+b]
        """)
        XCTAssertEqual(config.keybinds.action(for: trigger("cmd+e")), .toggleBrowser)
        XCTAssertEqual(config.keybinds.action(for: trigger("cmd+shift+b")), .toggleBrowser)
        XCTAssertNil(config.keybinds.action(for: trigger("cmd+b")))
        XCTAssertEqual(config.keybinds.firstTrigger(for: .toggleBrowser), trigger("cmd+e"))
    }

    func testAnEmptyListLeavesTheActionWithNoKeybinding() throws {
        let config = try load("""
        keybindings:
          toggle_browser: []
        """)
        XCTAssertNil(config.keybinds.firstTrigger(for: .toggleBrowser))
        XCTAssertNil(config.keybinds.action(for: trigger("cmd+b")))
        XCTAssertEqual(config.keybinds.firstTrigger(for: .toggleSidebar), trigger("cmd+s"))
        XCTAssertEqual(config.problems, [])
    }

    func testATriggerListedForOneActionIsTakenFromTheDefaultsOfAnother() throws {
        let config = try load("""
        keybindings:
          toggle_browser: cmd+s
        """)
        XCTAssertEqual(config.keybinds.action(for: trigger("cmd+s")), .toggleBrowser)
        XCTAssertEqual(config.keybinds.firstTrigger(for: .toggleSidebar), trigger("ctrl+cmd+s"))
        XCTAssertNil(config.keybinds.action(for: trigger("cmd+b")))
        XCTAssertEqual(config.problems, [])
    }

    func testTheSameTriggerUnderTwoActionsStaysWithTheFirst() throws {
        let config = try load("""
        keybindings:
          toggle_browser: cmd+e
          toggle_sidebar:
            - cmd+e
            - cmd+j
        """)
        XCTAssertEqual(config.keybinds.action(for: trigger("cmd+e")), .toggleBrowser)
        XCTAssertEqual(config.keybinds.firstTrigger(for: .toggleSidebar), trigger("cmd+j"))
        XCTAssertEqual(config.problems, [
            ConfigProblem(path: root, line: 4, message: "cmd+e is already bound to toggle_browser"),
        ])
    }

    func testProblemLinesCountFromOne() throws {
        XCTAssertEqual(try load("nope: 1").problems, [
            ConfigProblem(path: root, line: 1, message: "unknown section \"nope\""),
        ])
    }

    func testValuesThatCannotApplyAreProblemsAndTheRestApplies() throws {
        let config = try load("""
        fonts:
          size: 12
        ghostty:
          theme: dark
        # comment
        keybindings:
          toggle_everything: cmd+e
          toggle_sidebar: hyper+s
          toggle_browser:
            - cmd+j
            - [cmd+k]
            - meta+b
        """)
        XCTAssertEqual(config.problems, [
            ConfigProblem(path: root, line: 1, message: "unknown section \"fonts\""),
            ConfigProblem(path: root, line: 4, message: "unknown key \"ghostty.theme\""),
            ConfigProblem(path: root, line: 7, message: "unknown action \"toggle_everything\""),
            ConfigProblem(path: root, line: 8, message: "bad trigger \"hyper+s\": unknown modifier \"hyper\""),
            ConfigProblem(path: root, line: 11, message: "toggle_browser: expected a trigger or a list of triggers"),
            ConfigProblem(path: root, line: 12, message: "bad trigger \"meta+b\": unknown modifier \"meta\""),
        ])
        XCTAssertNil(config.keybinds.action(for: trigger("cmd+e")))
        XCTAssertEqual(config.keybinds.firstTrigger(for: .toggleSidebar), trigger("cmd+s"))
        XCTAssertEqual(config.keybinds.triggers[.toggleBrowser], [trigger("cmd+j")])
    }

    func testValuesOfTheWrongTypeAreProblems() throws {
        XCTAssertEqual(try load("keybindings: cmd+s").problems, [
            ConfigProblem(path: root, line: 1, message: "keybindings: expected a mapping"),
        ])
        XCTAssertEqual(try load("- keybindings").problems, [
            ConfigProblem(path: root, line: 1, message: "the Config: expected a mapping"),
        ])
        let config = try load("""
        ghostty:
          config_file: [a, b]
        keybindings:
          toggle_sidebar:
          toggle_browser: {cmd: b}
        """)
        XCTAssertEqual(config.problems, [
            ConfigProblem(path: root, line: 2, message: "ghostty.config_file: expected a path"),
            ConfigProblem(path: root, line: 4, message: "toggle_sidebar: expected a trigger or a list of triggers"),
            ConfigProblem(path: root, line: 5, message: "toggle_browser: expected a trigger or a list of triggers"),
        ])
        XCTAssertNil(config.ghosttyConfigFile)
        XCTAssertEqual(config.keybinds, Keybinds.defaults)
    }

    func testGhosttyConfigFileResolvesAgainstTheConfigAndExpandsHome() throws {
        let relative = try load([
            root: "ghostty:\n  config_file: ../ghostty/personal",
            "/cfg/ghostty/personal": "",
        ])
        XCTAssertEqual(relative.ghosttyConfigFile, "/cfg/ghostty/personal")
        XCTAssertEqual(relative.problems, [])

        let home = NSHomeDirectory()
        let fromHome = try load([
            root: "ghostty:\n  config_file: ~/ghostty/work",
            "\(home)/ghostty/work": "",
        ])
        XCTAssertEqual(fromHome.ghosttyConfigFile, "\(home)/ghostty/work")
        XCTAssertEqual(fromHome.problems, [])
    }

    func testAMissingGhosttyConfigFileIsAProblem() throws {
        let config = try load("ghostty:\n  config_file: /nowhere")
        XCTAssertEqual(config.ghosttyConfigFile, "/nowhere")
        XCTAssertEqual(config.problems, [
            ConfigProblem(path: root, line: 2, message: "ghostty.config_file /nowhere: not found"),
        ])
    }

    func testASyntaxErrorFailsTheWholeRead() {
        let badIndent = Config.load(path: root) { _ in "keybindings:\n  toggle_sidebar: cmd+s\n toggle_browser: cmd+b\n" }
        XCTAssertThrowsError(try badIndent.get()) { error in
            XCTAssertEqual((error as? ConfigSyntaxError)?.problem.line, 3)
            XCTAssertEqual((error as? ConfigSyntaxError)?.problem.path, root)
        }
        let duplicate = Config.load(path: root) { _ in "keybindings:\n  toggle_sidebar: cmd+s\n  toggle_sidebar: cmd+j\n" }
        XCTAssertThrowsError(try duplicate.get()) { error in
            XCTAssertEqual((error as? ConfigSyntaxError)?.problem.message, "duplicate key toggle_sidebar")
        }
    }

    func testASyntaxErrorKeepsTheLastGoodConfigAndShowsOnlyItself() throws {
        var loaded = LoadedConfig()
        loaded.update(with: Config.load(path: root) { _ in "keybindings:\n  toggle_browser: cmd+e\nnope: 1" })
        let good = loaded.config
        XCTAssertEqual(good.keybinds.firstTrigger(for: .toggleBrowser), trigger("cmd+e"))
        XCTAssertEqual(loaded.problems.map(\.message), ["unknown section \"nope\""])

        let syntaxError = Config.load(path: root) { _ in "keybindings: [" }
        loaded.update(with: syntaxError)
        XCTAssertEqual(loaded.config, good)
        XCTAssertThrowsError(try syntaxError.get()) { error in
            XCTAssertEqual(loaded.problems, [(error as! ConfigSyntaxError).problem])
        }

        loaded.update(with: Config.load(path: root) { _ in nil })
        XCTAssertEqual(loaded.config.keybinds, Keybinds.defaults)
        XCTAssertEqual(loaded.problems, [])
    }

    func testTriggersParseGhosttyNames() throws {
        XCTAssertEqual(try KeyTrigger("cmd+shift+left_bracket"), KeyTrigger(modifiers: [.command, .shift], key: .character("[")))
        XCTAssertEqual(try KeyTrigger("ctrl+cmd+s"), KeyTrigger(modifiers: [.control, .command], key: .character("s")))
        XCTAssertEqual(try KeyTrigger("control+command+S"), try KeyTrigger("ctrl+cmd+s"))
        XCTAssertEqual(try KeyTrigger("digit_1"), KeyTrigger(modifiers: [], key: .character("1")))
        XCTAssertEqual(try KeyTrigger("opt+left"), KeyTrigger(modifiers: .option, key: .special(.left)))
        XCTAssertEqual(try KeyTrigger("cmd+shift+left_bracket").symbol, "⇧⌘[")
        XCTAssertEqual(try KeyTrigger("ctrl+cmd+s").symbol, "⌃⌘S")
        XCTAssertThrowsError(try KeyTrigger("cmd+"))
        XCTAssertThrowsError(try KeyTrigger("cmd+nope"))
        XCTAssertThrowsError(try KeyTrigger("meta+s"))
    }

    func testTheTemplateIsAValidConfigThatChangesNothing() throws {
        let config = try load(Config.template)
        XCTAssertEqual(config.keybinds, Keybinds.defaults)
        XCTAssertNil(config.ghosttyConfigFile)
        XCTAssertEqual(config.problems, [])
    }

    func testTheKeybindingsTheTemplateShowsAreTheDefaults() throws {
        let shown = Config.template.split(separator: "\n").filter { $0.hasPrefix("#   toggle_") }.map { $0.dropFirst() }
        XCTAssertEqual(shown.count, ConfigAction.allCases.count)
        let config = try load("keybindings:\n" + shown.joined(separator: "\n"))
        XCTAssertEqual(config.keybinds, Keybinds.defaults)
        XCTAssertEqual(config.problems, [])
    }
}

final class ConfigFileSetTests: XCTestCase {
    func testIncludesResolveAgainstTheIncludingFile() {
        let files = [
            "/g/config": """
            font-size = 12
            config-file = keys/more
            """,
            "/g/keys/more": "config-file = \"../last\"",
            "/g/last": "",
        ]
        XCTAssertEqual(ConfigFileSet(root: "/g/config") { files[$0] }.files, ["/g/config", "/g/keys/more", "/g/last"])
    }

    func testMissingIncludesAreStillWatched() {
        let files = ["/g/config": "config-file = ?optional\nconfig-file = required"]
        XCTAssertEqual(ConfigFileSet(root: "/g/config") { files[$0] }.files, ["/g/config", "/g/optional", "/g/required"])
    }

    func testAnIncludeCycleIsReadOnce() {
        let files = ["/g/config": "config-file = other", "/g/other": "config-file = config"]
        var reads: [String] = []
        let set = ConfigFileSet(root: "/g/config") { reads.append($0); return files[$0] }
        XCTAssertEqual(set.files, ["/g/config", "/g/other"])
        XCTAssertEqual(reads, ["/g/config", "/g/other"])
    }
}
