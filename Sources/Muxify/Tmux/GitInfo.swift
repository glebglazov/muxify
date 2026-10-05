import Foundation

enum GitInfo {
    /// Current branch for the repository containing `path`, read straight from
    /// `.git/HEAD` (no git process). Handles worktrees and submodules where
    /// `.git` is a `gitdir:` pointer file. Returns a short SHA when detached.
    static func branch(at path: String) -> String? {
        guard !path.isEmpty else { return nil }
        let fm = FileManager.default
        var dir = path
        while true {
            let dotGit = (dir as NSString).appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: dotGit, isDirectory: &isDirectory) {
                guard let gitDir = isDirectory.boolValue ? dotGit : resolveGitFile(dotGit, relativeTo: dir) else {
                    return nil
                }
                return readHead(gitDir)
            }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent.isEmpty { return nil }
            dir = parent
        }
    }

    private static func resolveGitFile(_ file: String, relativeTo dir: String) -> String? {
        guard let content = try? String(contentsOfFile: file, encoding: .utf8),
              let line = content.split(separator: "\n").first,
              line.hasPrefix("gitdir:")
        else { return nil }
        let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        return target.hasPrefix("/") ? target : (dir as NSString).appendingPathComponent(target)
    }

    private static func readHead(_ gitDir: String) -> String? {
        let headFile = (gitDir as NSString).appendingPathComponent("HEAD")
        guard let head = try? String(contentsOfFile: headFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        let prefix = "ref: refs/heads/"
        if head.hasPrefix(prefix) { return String(head.dropFirst(prefix.count)) }
        return String(head.prefix(7))
    }
}
