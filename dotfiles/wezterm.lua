local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- Shift+Enter → ESC + CR, so Claude Code inserts a newline instead of
-- submitting the prompt. CSI-u ("\x1b[13;2u") also works in wezterm but
-- would require tmux-side decoding; ESC+CR needs nothing extra.
config.keys = {
  {
    key = 'Enter',
    mods = 'SHIFT',
    action = wezterm.action.SendString '\x1b\r',
  },
}

-- SSH via wezterm's built-in client. Critical: this bypasses Windows
-- ConPTY, which is what makes mouse scroll and CSI keys work end-to-end.
-- Two ways to connect:
--   1. From anywhere:  wezterm ssh user@host
--   2. Auto-connect on launch: uncomment the block below with your VM's
--      address and username, then launching wezterm opens straight in.
--
-- config.ssh_domains = {
--   { name = 'vm', remote_address = 'host.or.ip', username = 'you' },
-- }
-- config.default_domain = 'vm'

-- Scrollback and mouse behavior (both work because ConPTY is out of the
-- picture — mouse wheel in tmux panes scrolls per-pane as expected).
config.scrollback_lines = 10000
config.hide_mouse_cursor_when_typing = false

return config
