import Foundation

/// Reads a Remote Environment's own Config file over the SSH master (ADR 0010).
enum RemoteConfigFile {
    /// Prints the file's path, then `present` and its text, or `missing`.
    static let script = """
    file=${XDG_CONFIG_HOME:-$HOME/.config}/muxify/config.yaml
    printf '%s\\n' "$file"
    if [ -f "$file" ]; then
        printf 'present\\n'
        cat "$file"
    else
        printf 'missing\\n'
    fi
    """

    /// The file's path, and its text when it exists.
    static func parse(_ output: String) -> (path: String, text: String?)? {
        let lines = output.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false)
        guard lines.count >= 2, !lines[0].isEmpty else { return nil }
        switch lines[1] {
        case "present": return (String(lines[0]), lines.count > 2 ? String(lines[2]) : "")
        case "missing": return (String(lines[0]), nil)
        default: return nil
        }
    }
}
