# A repository is one Project, and its Worktrees are rows in the Project list

A Project directory can be a repository with several Worktrees, for example a bare repository with one Worktree folder per branch. Muxify asks git for the layout (the common git dir and `core.bare`), not the folder names. The repository is one Project. The New Topic and Add Project lists show one row per Worktree folder, `<repo>/<folder>`, and a Session label uses the same name. The main checkout of a plain repository is the Project folder itself, so its row and label are just `<repo>`. A Topic has at most one Session in each Project, so it uses one Worktree of a repository. A checkbox creates a new Worktree from the selected one: the branch is the Topic slug, at that Worktree's HEAD.

pop makes each Worktree its own Project. Muxify keeps pop's list but not pop's model, because a Topic's Sessions are the repositories it touches, and Settle has one Worktree per repository to clean up.

## Considered Options

- **Each Worktree is a Project, as in pop.** Rejected: one Topic could hold Sessions in two Worktrees of one repository, and a new Worktree becomes a new Project only after it is created.
- **One Project row per repository, with a separate Worktree picker.** Rejected: one more step, and the list did not match the one you know from pop.

## Consequences

- Every new Worktree, of a bare or a plain repository, goes to `$XDG_STATE_HOME/muxify/worktrees/<project>/<slug>` (`~/.local/state/muxify/worktrees/...` when `XDG_STATE_HOME` is not set), beside the Topic records. `<project>` is the Project's name, never its alias. The folder cannot be configured, and the Config has no `topics.worktree_dir`. Worktrees made before this rule stay where they are.
- A Worktree that another open Topic uses can still be picked. Its row says "Also in <Topic>". Each Topic gets its own Session there, because a Session name ends with the Topic slug.
- The Topic record remembers whether the Topic created its Worktree. Settle removes a Worktree only when it is inside Muxify's worktrees folder and the record says `worktree_created: true`, so the user's own Worktrees are never removed, wherever they are. Settle also keeps a Worktree that any live Session, of any Topic, uses. It keeps the branch, so Reopen can check the folder out again. These rules are the guard that lets two Topics share a Worktree.
- The check that a Window sits in the main working copy cannot assume that the Project folder is a checkout.
