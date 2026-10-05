# Muxify

A personal macOS front end for tmux. It has a sidebar of tmux windows, a terminal showing the selected window, and a browser panel beside the terminal. tmux owns sessions, windows and panes; Muxify adds the browser.

## Language

### tmux

**Session**:
A tmux session, usually one per project. Sessions group Windows in the sidebar.
_Avoid_: project, workspace

**Window**:
A tmux window: the item you pick in the sidebar. Opening it shows all of its Panes.
_Avoid_: tab, workspace

**Pane**:
One split of a Window, laid out by tmux.
_Avoid_: split, terminal

### Browser

**Browser**:
The web panel beside the terminal. Each Window has its own Browser, which remembers whether it is open and which Tabs it holds; switching Windows switches the Browser too.
_Avoid_: webview, inspector, sidebar browser

**Tab**:
One page in a Window's Browser, with its own back/forward history. "Tab" never means a tmux Window.
_Avoid_: page (when you mean the Tab itself), browser window
