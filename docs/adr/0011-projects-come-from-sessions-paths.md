# Projects come from `sessions.paths`, and a repository is still one Project

Upstream Muxify added `sessions.paths`: folders, each with a `depth`, that a Command Palette offers as Sessions. It called each folder or git worktree a Session Path. Our `projects` list did the same job for Topics. We keep one concept, the Project, and one Config section with upstream's name, `sessions.paths`, which takes upstream's `path` and `depth`. Upstream Configs keep their key, so the branch does not move the user's folders to a new section. `path` can also be a glob, and each match is a root that `depth` applies to. `display_depth` on an entry sets how many trailing folder names make the Project's name, 1 by default. `sessions.aliases` replaces `projects_aliases`.

We keep our own rule from [ADR 0008](0008-a-repository-is-one-project.md): a repository is one Project, and its Worktrees are rows of it, found from git's layout, so bare repositories work. Upstream's rule makes each worktree its own Session Path and finds worktrees only below a `.git` folder.

## Considered Options

- **Upstream's `path` and `depth` only.** Rejected: `depth` takes every level down to it, so `~/Dev` with depth 2 makes each org folder a Project too. A new org folder needs a Config edit.
- **Upstream's names: the last folder name, with the parent folder in front on a clash.** Rejected: Topic records and Worktree folders use the Project's name, and a clash rule changes a name when another folder appears.
- **Keep both `projects` and `sessions.paths`.** Rejected: two lists of the same folders that can disagree.
- **Rename the section to `projects.paths`, after the concept.** Rejected: every upstream Config then loads with a problem and loses its folders until it is edited.

## Consequences

- An old `projects` section or `projects_aliases` shows in the Config problems banner and names the `sessions` key that replaces it. Muxify does not read it.
- Muxify finds Projects on the machine of each Environment, as upstream did. Topics stay on this Mac.
- A No Topic Session in a Worktree is named `<project>/<folder>`. Muxify finds a Project's Session by its folder, not by its name. In a tmux name, `.` and `:` become `_` and spaces go.
