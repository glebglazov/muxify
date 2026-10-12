# Focus is where input goes, and Maximize shows one side alone

Muxify used "Focus" for showing one of a Window's Terminal and Browser alone with the Sidebar hidden, and "the keyboard" for where input goes. Other apps and macOS use "focus" for where input goes, so `focus_terminal` read as "type into the Terminal" but hid the Browser and the Sidebar. We now call the layout **Maximize** and where input goes **Focus**. The keybinding actions follow: `toggle_maximize`, `toggle_maximize_terminal` and `toggle_maximize_browser` show one side alone, and `focus_terminal` and `focus_browser` only move Focus. The defaults follow one pattern for each side: ⌘J and ⌘B toggle, ⌘⇧J and ⌘⇧B move Focus, ⌥⌘J and ⌥⌘B Maximize. The old names `toggle_focus` and `move_keyboard_to_terminal` show a Config problem. `focus_terminal` and `focus_browser` keep their names with the new meaning, so a Config that binds them changes behavior without a problem.

## Considered Options

- **Keep Focus for the layout and "the keyboard" for input.** Rejected: every user reads "focus" as where input goes, and `move_keyboard_to_terminal` had no Browser twin because the word was awkward.
- **Zoom for the layout.** Rejected: tmux zooms a Pane, and Ghostty's `toggle_split_zoom` is on the same default key.
