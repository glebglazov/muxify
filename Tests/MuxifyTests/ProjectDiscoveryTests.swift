import XCTest
@testable import MuxifyCore

final class ProjectDiscoveryTests: XCTestCase {
    private func load(_ text: String, at path: String = "/cfg/muxify/config.yaml") throws -> Config {
        try Config.load(path: path) { _ in text }.get()
    }

    func testProjectsPathsTakeAGlobADepthAndADisplayDepth() throws {
        let config = try load("""
        projects:
          paths:
            - path: ~/Dev/*/*
              display_depth: 2
            - path: ~/projects
              depth: 1
            - path: work
            - path: "~"
        """)
        XCTAssertEqual(config.problems, [])
        XCTAssertEqual(config.projectRoots, [
            ProjectRoot(path: "~/Dev/*/*", depth: 0, displayDepth: 2),
            ProjectRoot(path: "~/projects", depth: 1, displayDepth: 1),
            ProjectRoot(path: "/cfg/muxify/work", depth: 0, displayDepth: 1),
            ProjectRoot(path: "~", depth: 0, displayDepth: 1),
        ], "~ stays for the machine that looks; a relative path starts at the Config's folder")
        XCTAssertEqual(config.projects, [], "loading never looks on disk")
    }

    func testTheOldProjectsListAndSessionsPathsAreProblemsThatNameTheirNewPlace() throws {
        let config = try load("""
        projects:
          - path: ~/Dev/*
        projects_aliases:
          - ~/Dev/x: X
        sessions:
          paths: [{path: ~/src}]
        """)
        XCTAssertEqual(config.problems.map(\.message), [
            "projects: the list moved to projects.paths",
            "projects_aliases moved to projects.aliases",
            "sessions.paths moved to projects.paths",
        ])
        XCTAssertEqual(config.projectRoots, [])
    }

    func testWrongProjectsPathsShapesAreProblemsAndSkipTheirEntry() throws {
        for entry in ["wrong", "{display_depth: 2}", "{path: 42}", "{path: true}", "{path: ''}",
                      "{path: /tmp, display_depth: 0}", "{path: /tmp, display_depth: -1}", "{path: /tmp, display_depth: '2'}",
                      "{path: /tmp, depth: -1}", "{path: /tmp, depth: 1.5}", "{path: /tmp, color: red}"] {
            let config = try load("projects:\n  paths: [\(entry)]")
            XCTAssertEqual(config.problems.count, 1, entry)
            XCTAssertEqual(config.problems.first?.line, 2, entry)
            XCTAssertEqual(config.projectRoots, [], entry)
        }
        for text in ["projects: 42", "projects:\n  paths: {}", "projects:\n  folders: []"] {
            XCTAssertFalse(try load(text).problems.isEmpty, text)
        }
    }

    func testDiscoveryNamesByDisplayDepthKeepsTheFirstRootAndFindsFoldersMadeLater() throws {
        let root = try TestDirectory()
        for name in ["alpha", "beta"] {
            try FileManager.default.createDirectory(at: root.url.appendingPathComponent("work/" + name), withIntermediateDirectories: true)
        }
        try Data().write(to: root.url.appendingPathComponent("work/file"))
        let roots = [ProjectRoot(path: root.url.path + "/work/*", displayDepth: 2), ProjectRoot(path: root.url.path + "/work/alpha")]
        XCTAssertEqual(ProjectDiscovery.discover(roots, aliases: [:]).map(\.name), ["work/alpha", "work/beta"])
        for name in ["gamma.app", "my notes"] {
            try FileManager.default.createDirectory(at: root.url.appendingPathComponent("work/" + name), withIntermediateDirectories: true)
        }
        XCTAssertEqual(ProjectDiscovery.discover(roots, aliases: [:]).map(\.name),
                       ["work/alpha", "work/beta", "work/gamma_app", "work/mynotes"],
                       "a folder made later is a Project, named as tmux takes it")
    }

    func testDepthListsSubfoldersAndARepositoryIsOneProjectWithItsWorktrees() throws {
        let directory = try TestDirectory()
        // git prints real paths: /private/var, not /var.
        let home = String(cString: realpath(directory.url.path, nil))
        let fm = FileManager.default
        for folder in ["projects/app/src", "projects/lib/nested/deep", "projects/.cache", "projects/lib/.hidden", "dotfiles", "trees"] {
            try fm.createDirectory(atPath: "\(home)/\(folder)", withIntermediateDirectories: true)
        }
        let git = { (args: [String]) in
            _ = try CommandRunner().run(CommandInvocation(executable: "/usr/bin/env", arguments: ["git"] + args),
                                        environment: ["HOME": home, "PATH": "/usr/bin:/bin:/opt/homebrew/bin",
                                                      "GIT_CONFIG_NOSYSTEM": "1"])
        }
        try git(["-C", "\(home)/projects/app", "init", "-q", "-b", "main"])
        try git(["-C", "\(home)/projects/app", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "x"])
        try git(["-C", "\(home)/projects/app", "worktree", "add", "-q", "\(home)/trees/fix", "-b", "fix"])

        let roots = [
            ProjectRoot(path: "~/projects/", depth: 2),
            ProjectRoot(path: "~/dotfiles"),
            ProjectRoot(path: "~/missing", depth: 1),
            ProjectRoot(path: "~/trees", depth: 1),
        ]
        let output = try CommandRunner().run(
            CommandInvocation(executable: "/bin/sh",
                              arguments: ["-c", ProjectDiscovery.script, "muxify"] + ProjectDiscovery.arguments(for: roots)),
            environment: ["HOME": home, "PATH": "/usr/bin:/bin:/opt/homebrew/bin"]
        )
        let projects = ProjectDiscovery.projects(in: output, roots: roots, aliases: ["~/dotfiles": "Dotfiles"])
        // Foundation's standardized paths drop /private.
        let shown = (home as NSString).standardizingPath
        XCTAssertEqual(projects.map { $0.path.replacingOccurrences(of: shown, with: "~") },
                       ["~/projects/app", "~/projects/lib", "~/projects/lib/nested", "~/dotfiles"],
                       "no repository subfolder, Worktree, hidden or missing folder is a Project")
        XCTAssertEqual(projects[0].layout, .plainRepository([
            Worktree(path: "\(shown)/projects/app", branch: "main"), Worktree(path: "\(shown)/trees/fix", branch: "fix"),
        ]))
        XCTAssertEqual(ProjectChoice.choices(of: projects[0]).map(\.name), ["app", "app/fix"])
        XCTAssertEqual(projects[3].displayName, "Dotfiles", "an alias with ~ means the home folder of the machine that looks")
    }

    func testALinkedWorktreeThatSortsFirstIsARowOfItsRepository() throws {
        let directory = try TestDirectory()
        let home = String(cString: realpath(directory.url.path, nil))
        try FileManager.default.createDirectory(atPath: "\(home)/code/zzz", withIntermediateDirectories: true)
        let git = { (args: [String]) in
            _ = try CommandRunner().run(CommandInvocation(executable: "/usr/bin/env", arguments: ["git"] + args),
                                        environment: ["HOME": home, "PATH": "/usr/bin:/bin:/opt/homebrew/bin",
                                                      "GIT_CONFIG_NOSYSTEM": "1"])
        }
        try git(["-C", "\(home)/code/zzz", "init", "-q", "-b", "main"])
        try git(["-C", "\(home)/code/zzz", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "x"])
        try git(["-C", "\(home)/code/zzz", "worktree", "add", "-q", "\(home)/code/aaa-wt", "-b", "fix"])

        let roots = [ProjectRoot(path: "\(home)/code/*")]
        let output = try CommandRunner().run(
            CommandInvocation(executable: "/bin/sh",
                              arguments: ["-c", ProjectDiscovery.script, "muxify"] + ProjectDiscovery.arguments(for: roots)),
            environment: ["HOME": home, "PATH": "/usr/bin:/bin:/opt/homebrew/bin"]
        )
        let projects = ProjectDiscovery.projects(in: output, roots: roots, aliases: [:])
        XCTAssertEqual(projects.map(\.name), ["zzz"], "the repository is the Project, not its Worktree")
        XCTAssertEqual(ProjectChoice.choices(of: projects[0]).map(\.name), ["zzz", "zzz/aaa-wt"])
    }

    func testRemoteConfigFileOutput() {
        XCTAssertEqual(RemoteConfigFile.parse("/h/.config/muxify/config.yaml\npresent\nui:\n  header_height: 30\n")?.text,
                       "ui:\n  header_height: 30\n")
        XCTAssertEqual(RemoteConfigFile.parse("/h/.config/muxify/config.yaml\npresent\n")?.text, "")
        let missing = RemoteConfigFile.parse("/h/.config/muxify/config.yaml\nmissing\n")
        XCTAssertEqual(missing?.path, "/h/.config/muxify/config.yaml")
        XCTAssertNil(missing?.text)
        XCTAssertNil(RemoteConfigFile.parse("Welcome!\n"))
    }
}
