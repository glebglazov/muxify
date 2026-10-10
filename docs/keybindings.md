# Keybindings

## Configurable actions

These keybindings work throughout Muxify, including while a Browser page or its
address bar has focus. All available `keybindings` actions are listed below.

| Action | Default shortcuts | What it does |
| --- | --- | --- |
| `new_app_window` | ⌘N | Open a new Local Muxify App Window |
| `new_topic` | Unbound | Open New Topic in the palette |
| `new_topic_from_pane` | ⌘⇧T | Open Move for the current Pane |
| `move_session_to_topic` | ⌘⇧M | Open Move for the selected Window's Session, in the Command Palette's view |
| `add_project_to_topic` | ⌘⇧A | Open Add a Project for the Active Topic in the palette |
| `snooze_topic` | ⌥⌘S | Snooze the Active Topic, then open the Next Topic |
| `zen_mode` | ⇧⌥⌘S | Start Zen, which Snoozes every open Topic except the Active Topic; while Zen is on, end it. While the Active Topic is No Topic, it only ends Zen |
| `settle_topic` | Unbound | Settle the Active Topic, then open the Next Topic |
| `toggle_sidebar` | ⌘S, ⌃⌘S | Show or hide the Sidebar |
| `toggle_terminal` | ⌘J | Show or hide the current Window's Terminal. It does nothing while the Terminal is the only side shown |
| `toggle_browser` | ⌘B | Show or hide the current Window's Browser. It does nothing while the Browser is the only side shown |
| `toggle_focus` | ⇧⌘↩ | Focus the side the keyboard is in: show it alone and hide the Sidebar. While Focus is on, end it |
| `focus_terminal` | ⌥⌘T | Focus the Terminal and move the keyboard into it. While the Terminal is in Focus, end Focus |
| `focus_browser` | ⌥⌘B | Focus the Browser and move the keyboard into it, also when the Browser is hidden. While the Browser is in Focus, end Focus |
| `move_keyboard_to_terminal` | ⌃ + backquote | Move the keyboard into the Terminal of the current App Window |
| `select_window_1` | ⌘1 | Select the first Window in the current Session |
| `select_window_2` | ⌘2 | Select the second Window |
| `select_window_3` | ⌘3 | Select the third Window |
| `select_window_4` | ⌘4 | Select the fourth Window |
| `select_window_5` | ⌘5 | Select the fifth Window |
| `select_window_6` | ⌘6 | Select the sixth Window |
| `select_window_7` | ⌘7 | Select the seventh Window |
| `select_window_8` | ⌘8 | Select the eighth Window |
| `select_window_9` | ⌘9 | Select the ninth Window, not the last one |
| `select_next_window` | Unbound | Select the next Window, wrapping to the first |
| `select_prev_window` | Unbound | Select the previous Window, wrapping to the last |

The default [Command Palettes](configuration.md#command-palettes) are
**Commands** on ⌘⇧P and **Go to…** on ⌘P. `open_switcher` is gone.
A Config that still names it shows a problem.

Commands also lists Move Pane, Move Window, Move Session, Move Pane with Active
Tab, Add a Project, Snooze Topic, Settle Topic, and Zen or End Zen. These use the
current item and appear when that item is available. Back returns from an input
step to the Commands search.

Move opens for a Pane with ⌘⇧T or a Session with ⌘⇧M. Its chips select
Pane, Window or Session. For a Pane or Window, New Topic is the first row.
A Pane can also move to a New Window. The ＋ Tab chip includes the active
Browser Tab and keeps its history. A Topic that cannot accept the move shows
the reason. Move does nothing while `sidebar.topics` is off.

Every Action uses the palette's view, including Actions from Sidebar and menu
bar items. ⎋ closes without a change. ⌫ in an empty field goes back one step.
A step that kills a process needs ⌘↩ to confirm.

Focus never changes the toggles. When Focus ends, the Window shows what its
toggles say. A Sidebar, Terminal or Browser toggle used during Focus first keeps
what is on screen, then ends Focus and applies. Focus on a side that is already
alone, with the Sidebar hidden, has nothing to hide and does nothing. Each Window
keeps its own Focus: the Sidebar shows again in a Window without Focus. ⇧⌘↩ is
also Ghostty's default for `toggle_split_zoom`; Muxify's binding takes
precedence, as for every Muxify keybinding.

All tmux Window navigation stays within the focused App Window's current Session
and follows sidebar order, not tmux's window indices.
Switching Windows also restores that Window's Browser and moves the keyboard to
its Terminal, or to its Browser when its Terminal is hidden. If a
numbered position does not exist, the shortcut does nothing.

Use **Muxify → Open Config** to open `~/.config/muxify/config.yaml` (or
`$XDG_CONFIG_HOME/muxify/config.yaml`). This example lists every configurable
action, keeps the default bindings, and assigns optional next/previous shortcuts:

```yaml
keybindings:
  new_app_window: cmd+n
  new_topic: []
  new_topic_from_pane: cmd+shift+t
  move_session_to_topic: cmd+shift+m
  add_project_to_topic: cmd+shift+a
  snooze_topic: alt+cmd+s
  zen_mode: shift+alt+cmd+s
  settle_topic: []
  toggle_sidebar: [cmd+s, ctrl+cmd+s]
  toggle_terminal: cmd+j
  toggle_browser: cmd+b
  toggle_focus: shift+cmd+enter
  focus_terminal: alt+cmd+t
  focus_browser: alt+cmd+b
  move_keyboard_to_terminal: ctrl+backquote
  select_window_1: cmd+1
  select_window_2: cmd+2
  select_window_3: cmd+3
  select_window_4: cmd+4
  select_window_5: cmd+5
  select_window_6: cmd+6
  select_window_7: cmd+7
  select_window_8: cmd+8
  select_window_9: cmd+9
  # These two actions are unbound by default.
  select_next_window: ctrl+cmd+right
  select_prev_window: ctrl+cmd+left
```

Triggers use Ghostty-style names: `cmd`, `ctrl`, `alt` (Option), and `shift`,
followed by a character or a named key such as `left`, `right`, `tab`, or
`left_bracket`. An action accepts one trigger or a list, such as
`select_window_2: [cmd+2, ctrl+cmd+2]`. A character names the key that types
it with ⌘ held on the current keyboard layout, as menu shortcuts do. So on a
non-Latin layout such as Russian, `cmd+p` is still the key labelled P, and
`cmd+shift+1` is the 1 key, not `!`.

Actions not listed keep their defaults. Naming an action replaces its defaults;
`[]` disables it (for example, `select_window_9: []`). A trigger explicitly
assigned to an action is removed from other actions' defaults. If two actions
explicitly claim the same trigger, the first keeps it and Muxify reports the
conflict. Muxify reloads the Config when it changes. Its bindings take precedence
over Ghostty and Browser page bindings, but only inside Muxify—not while another
app is active.

To change New App Window, use `new_app_window: cmd+shift+n`; use
`new_app_window: []` to disable its shortcuts. This also removes the terminal's
default ⌘N behavior. New tmux Session remains available from the File menu.

Move Keyboard to Terminal defaults to Control + backquote, leaving Command + backquote
for macOS App Window switching. Use `move_keyboard_to_terminal: []` to disable it, or
`move_keyboard_to_terminal: cmd+backquote` to restore the old shortcut at the cost of native
App Window switching.

## Command Palette keybindings

A [Command Palette](configuration.md#command-palettes)'s own `keybinding` is
set on the palette and follows the rules above. While a palette is open, these
actions win over every other keybinding. They are configured under
`keybindings.command_palette`, with the same rules among themselves, and never
conflict with the actions above:

| Action | Default shortcuts | What it does |
| --- | --- | --- |
| `jump_to` | Enter | Jump to the highlighted result, or run the highlighted action |
| `new_session` | ⌘Enter | Start another Session in the highlighted Project or Worktree, and switch to it |
| `select_next` | Down, ⌃J | Highlight the next result or action |
| `select_prev` | Up, ⌃K | Highlight the previous result or action |
| `show_actions` | ⌘K | Show or hide the actions menu |
| `copy_path` | ⌘C | Copy the result's folder |
| `copy_target` | ⌘⇧C | Copy the result's tmux target or Pane ID |
| `paste_path` | ⌃Y | Type the result's folder, as one shell word, at the prompt of the current Pane |
| `snooze` | ⌃S | Open Snooze for the highlighted open, Dormant or Snoozed Topic |
| `move` | Unbound | Open Move for the highlighted result |
| `add_project` | Unbound | Add a Project to the highlighted Topic |
| `rename` | Unbound | Rename the highlighted Topic or Window |
| `suggest` | Unbound | Suggest a title for the highlighted Topic |
| `zen` | Unbound | Start Zen for the highlighted Topic |
| `settle` | Unbound | Settle the highlighted Topic |
| `forget` | Unbound | Forget the highlighted Topic |
| `unsnooze` | Unbound | Unsnooze the highlighted Topic |
| `reopen` | Unbound | Reopen the highlighted Topic |
| `start_fresh` | Unbound | Start Fresh for the highlighted Topic |
| `pin` | Unbound | Pin the highlighted Topic |
| `unpin` | Unbound | Unpin the highlighted Topic |
| `remove_from_topic` | Unbound | Remove the highlighted Session or Window from its Topic |
| `new_window` | Unbound | Create a Window in the highlighted Session |
| `reveal` | Unbound | Reveal the result's folder in Finder |
| `kill_window` | Unbound | Confirm a kill of the highlighted Window |
| `move_pane` | ⌥1 | Select the Pane chip in Move |
| `move_window` | ⌥2 | Select the Window chip in Move |
| `move_session` | ⌥3 | Select the Session chip in Move |
| `include_tab` | ⌥T | Turn the ＋ Tab chip on or off in Move |
| `new_worktree` | ⌥W | Turn the New Worktree option on or off when available |
| `suggest_title` | ⌥S | Suggest a Topic title when available |

```yaml
keybindings:
  command_palette:
    jump_to: enter
    select_next: [down, ctrl+j, ctrl+n]
    copy_target: []
```

⎋ and ⌘1–⌘5 (the source chips) are not configurable. With no results, ⌘C
copies the search text.

## Built-in shortcuts

These shortcuts are not configurable as actions in Muxify's `keybindings`
section. Configured Muxify bindings still take precedence over them. When the
terminal has focus, Ghostty bindings can take precedence over menu shortcuts.

| Shortcut | Action |
| --- | --- |
| ⌘ + backquote / ⌘⇧ + backquote | Cycle App Windows forward / backward (macOS) |
| ⌘⇧, | Reload the Muxify Config and Ghostty config |

**Browser shortcuts** apply when the Browser has focus. Menu clicks work even
when it does not. New Tab and Open Location can reveal a hidden Browser:

| Shortcut | Action |
| --- | --- |
| ⌘T | Open a new Browser Tab |
| ⌘L | Focus the address bar, opening the Browser if hidden |
| ⌘W | Close the active Browser Tab |
| ⌘⇧] or ⌃Tab | Select the next Browser Tab |
| ⌘⇧[ or ⌃⇧Tab | Select the previous Browser Tab |
| ⌘[ | Go back |
| ⌘] | Go forward |
| ⌘R | Reload the page, or stop it while loading |
| ⌘⇧C | Copy the active Browser Tab's current URL and show a “Copied URL” confirmation |
| ⌘⌥I | Open or focus Developer Tools for the active Browser Tab |
| Enter (address bar) | Navigate to the entered URL or search |
| Escape (address bar) | Restore the current URL and focus the page |

The ⌃Tab shortcuts also require the Browser to be open. ⌘W never closes the
Muxify app window; when the terminal has focus, it does nothing unless you
assign it to a configurable action.

Developer Tools are also available from **Browser → Show Developer Tools**,
the Browser's **⋯** menu, or **Inspect Element** in a page's right-click menu.
They inspect the existing Tab, with its current cookies, DOM and JavaScript
state, and close when that Tab closes. Opening the in-app WebKit inspector is
best-effort because it uses runtime-checked private APIs; if unavailable, inspect
Muxify's Tab from Safari's Develop menu instead.

Other terminal keybindings come from your Ghostty config and tmux bindings,
not the Muxify Config.

**Simulator input** is handled by its web page after clicking the Device screen.
Drag to swipe and type ordinary keys/modifiers; losing focus or disconnecting
releases held input. Home, rotation, Start Device and Stop Device are web controls,
not desktop menu actions. Browser/OS-reserved shortcuts and Muxify's configured
bindings remain on the Mac. There is no `toggle_simulator` action or native phone
toggle; open the Simulator Server's URL as an ordinary Browser Tab.
