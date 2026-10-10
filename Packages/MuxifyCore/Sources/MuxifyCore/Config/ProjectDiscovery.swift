import Foundation

/// Finds the Projects of `projects.paths` on one machine, with one script that runs here or over a Remote
/// Environment's SSH master. Each repository it finds comes with its Worktrees, read from git's layout.
public enum ProjectDiscovery {
    /// Takes each root's path and depth as a pair of arguments. Prints `H` and the home folder, `R` and the
    /// root's index when a root starts, then for each folder `D`, the folder, its kind (`directory`, `plain` or
    /// `bare`) and its real path, followed by its `git worktree list --porcelain` lines after `W`.
    /// Missing roots and hidden folders are skipped.
    public static let script = """
    s='\(Tmux.separator)'
    nl='
    '
    printf 'H%s%s\\n' "$s" "$HOME"
    index=0
    while [ "$#" -ge 2 ]; do
        pattern=$1
        depth=$2
        shift 2
        case $pattern in
            "~") pattern=$HOME ;;
            "~/"*) pattern=$HOME/${pattern#"~/"} ;;
        esac
        printf 'R%s%s\\n' "$s" "$index"
        index=$((index + 1))
        old=$IFS
        IFS=$nl
        for root in $pattern; do
            IFS=$old
            [ "$root" = / ] || root=${root%/}
            [ -d "$root" ] || continue
            if [ "$depth" -eq 0 ]; then
                printf '%s\\n' "$root"
            else
                find "$root" -mindepth 1 -maxdepth "$depth" -name '.*' -prune -o -type d -print 2>/dev/null
            fi | while IFS= read -r dir; do
                kind=directory
                if [ -e "$dir/.git" ] || { [ -f "$dir/HEAD" ] && [ -d "$dir/objects" ]; }; then
                    if [ "$(git -C "$dir" config --bool core.bare 2>/dev/null)" = true ]; then
                        kind=bare
                    elif top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) \\
                        && [ "$(cd "$dir" && pwd -P)" = "$(cd "$top" && pwd -P)" ]; then
                        kind=plain
                    fi
                fi
                printf 'D%s%s%s%s%s%s\\n' "$s" "$dir" "$s" "$kind" "$s" "$(cd "$dir" && pwd -P)"
                [ "$kind" = directory ] && continue
                git -C "$dir" worktree list --porcelain 2>/dev/null | while IFS= read -r line; do
                    printf 'W%s%s\\n' "$s" "$line"
                done
            done
        done
        IFS=$old
    done
    """

    public static func arguments(for roots: [ProjectRoot]) -> [String] {
        roots.flatMap { [$0.path, String($0.depth)] }
    }

    /// The Projects in the script's output, in root order and then by path. The first root to find a folder
    /// names it. A folder inside a repository the script found is not a Project of its own: it is that
    /// repository's subfolder or Worktree. `aliases` maps a path as the Config wrote it, `~` included,
    /// to its alias.
    public static func projects(in output: String, roots: [ProjectRoot], aliases: [String: String]) -> [Project] {
        var home = ""
        var found: [Found] = []
        var root = 0
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let fields = line.components(separatedBy: Tmux.separator)
            switch fields.first {
            case "H" where fields.count == 2: home = fields[1]
            case "R" where fields.count == 2: root = Int(fields[1]) ?? root
            case "D" where fields.count == 4:
                found.append(Found(root: root, path: (fields[1] as NSString).standardizingPath, kind: fields[2],
                                   real: (fields[3] as NSString).standardizingPath))
            case "W" where fields.count == 2 && !found.isEmpty:
                found[found.count - 1].worktrees.append(fields[1])
            default: continue
            }
        }
        let expandedAliases = Dictionary(aliases.map { (expand($0.key, home: home), $0.value) }, uniquingKeysWith: { first, _ in first })
        var projects: [Project] = []
        var repositoryFolders: [String] = []
        let ordered = found.enumerated().sorted { ($0.element.root, $0.element.path) < ($1.element.root, $1.element.path) }.map(\.element)
        let mainRepositories = ordered.filter(\.isMainRepository).map(\.real)
        for entry in ordered where roots.indices.contains(entry.root) {
            let inside = { (folder: String) in isInside(entry.path, folder) }
            guard !projects.contains(where: { $0.path == entry.path }), !repositoryFolders.contains(where: inside) else { continue }
            // A linked Worktree whose repository was also found is a row of that Project, whichever sorts first.
            if entry.kind != "directory", !entry.isMainRepository, let main = entry.mainCheckout,
               mainRepositories.contains(where: { isInside(main, $0) }) { continue }
            let layout = ProjectLayout(kind: entry.kind, worktreeList: entry.worktrees.joined(separator: "\n"),
                                       path: entry.path, realPath: entry.real)
            if entry.kind != "directory" { repositoryFolders += [entry.path] + layout.worktrees.map(\.path) }
            let name = entry.path.split(separator: "/").suffix(roots[entry.root].displayDepth)
                .map { Project.sessionName(String($0)) }.joined(separator: "/")
            guard !name.isEmpty else { continue }
            projects.append(Project(path: entry.path, name: name, alias: expandedAliases[entry.path], layout: layout))
        }
        return projects
    }

    /// Runs the script on this Mac.
    public static func discover(_ roots: [ProjectRoot], aliases: [String: String]) -> [Project] {
        guard !roots.isEmpty,
              let output = try? Shell.run("/bin/sh", ["-c", script, "muxify"] + arguments(for: roots)) else { return [] }
        return projects(in: output, roots: roots, aliases: aliases)
    }


    private static func expand(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return ((home as NSString).appendingPathComponent(String(path.dropFirst(2))) as NSString).standardizingPath }
        return (path as NSString).standardizingPath
    }
}

/// One folder the script reported, with its `git worktree list --porcelain` lines.
private struct Found {
    let root: Int
    let path: String
    let kind: String
    /// With symlinks resolved, as git reports paths.
    let real: String
    var worktrees: [String] = []

    /// git lists the main checkout, or the bare repository, first.
    var mainCheckout: String? {
        worktrees.first { $0.hasPrefix("worktree ") }.map { (String($0.dropFirst(9)) as NSString).standardizingPath }
    }

    /// A repository's own folder, not one of its linked Worktrees. A bare layout's main entry is the
    /// `.bare` folder inside it.
    var isMainRepository: Bool {
        kind != "directory" && mainCheckout.map { isInside($0, real) } == true
    }
}

private func isInside(_ path: String, _ folder: String) -> Bool {
    path == folder || path.hasPrefix(folder + "/")
}
