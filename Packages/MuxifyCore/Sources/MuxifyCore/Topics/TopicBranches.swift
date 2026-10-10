import Foundation

public struct TopicBranches: Equatable {
    private let values: [String: String]

    public init(records: [TopicRecord] = [], paths: [String] = [], read: (String) -> String? = { _ in nil }) {
        let paths = Set(paths.map { ($0 as NSString).standardizingPath }).union(records.filter { $0.settledAt == nil }.flatMap(\.sessions).compactMap { session -> String? in
            guard let path = session["worktree_path"]?.string, !path.isEmpty else { return nil }
            return (path as NSString).standardizingPath
        })
        var values: [String: String] = [:]
        var attempted: Set<String> = []
        var contents: [String: String] = [:]
        func cachedRead(_ path: String) -> String? {
            if attempted.insert(path).inserted { contents[path] = read(path) }
            return contents[path]
        }
        for original in paths where !original.isEmpty {
            var path = original
            while !path.isEmpty {
                let headPath: String
                if let pointer = cachedRead(path + "/.git")?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    guard pointer.hasPrefix("gitdir: ") else { break }
                    let gitdir = String(pointer.dropFirst(8))
                    guard !gitdir.isEmpty, !gitdir.contains("\n"), !gitdir.contains("\r"), !gitdir.contains("\0") else { break }
                    let directory = (gitdir as NSString).isAbsolutePath ? gitdir : path + "/" + gitdir
                    headPath = ((directory as NSString).standardizingPath as NSString).appendingPathComponent("HEAD")
                } else {
                    // The main checkout of a plain repository has a `.git` folder, not a `gitdir:` file.
                    headPath = path + "/.git/HEAD"
                }
                guard let head = cachedRead(headPath)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    let parent = (path as NSString).deletingLastPathComponent
                    if parent == path { break }
                    path = parent
                    continue
                }
                guard head.hasPrefix("ref: refs/heads/") else { break }
                let branch = String(head.dropFirst(16))
                guard !branch.isEmpty, branch.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
                      branch.rangeOfCharacter(from: .controlCharacters) == nil else { break }
                values[original] = branch
                break
            }
        }
        self.values = values
    }

    public subscript(worktreePath: String) -> String? {
        values[(worktreePath as NSString).standardizingPath]
    }
}
