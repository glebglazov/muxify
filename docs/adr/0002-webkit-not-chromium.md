# The Browser uses WebKit, not Chromium

The Browser is a WKWebView. "Like ChatGPT" meant the layout and feel of a side panel with navigation and an omnibox, not Atlas's embedded Chromium engine. Embedding Chromium would mean shipping and updating a browser engine for a personal tool.

The cost: Chrome extensions, Chrome profiles and CDP-based automation aren't available. If agents running in tmux need to drive the Browser over CDP, revisit this decision.
