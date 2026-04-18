# Claude Code over Windows → SSH → tmux → Linux VM

Configuration for using Claude Code on a remote Linux VM from a Windows
host. Covers two terminal options: WezTerm (recommended) and Alacritty
(fallback with limitations noted below).

## Background: Windows ConPTY

Windows ConPTY is the pseudoconsole layer that wraps console applications
such as `ssh.exe`. On its input side, ConPTY interprets CSI escape
sequences (those starting with `\x1b[`) and strips them before they reach
the child process. This affects two things in this stack:

- **Shift+Enter via CSI-u (`\x1b[13;2u`).** The widely-recommended binding
  for Shift+Enter → newline does not reach ssh on Windows. A lone ESC
  (without `[`) passes through unchanged.
- **Mouse reporting.** Every mouse protocol (X10, 1000, SGR/1006,
  urxvt/1015) begins with `\x1b[`. Mouse events from the terminal are
  stripped before tmux can receive them.

Verification: bind Shift+Enter to `"X\x1b[13;2uY"` and run `showkey -a`
over SSH. Only `X` and `Y` arrive. Change to `"X\x1bY"` and ESC appears
between them. For mouse, `showkey -a` with reporting enabled
(`printf '\e[?1006h\e[?1000h'`) shows no bytes on wheel/click.

A workaround exists for Shift+Enter (`ESC + CR`) because it contains no
`[`. No equivalent workaround exists for mouse reporting, which is CSI-
based by protocol.

## Alacritty in this stack

Alacritty on Windows spawns its child process through ConPTY. This is
required — ConPTY is the Windows API for launching console applications,
and Alacritty has no non-ConPTY mode. Swapping which SSH implementation
runs as the child (Windows OpenSSH, MSYS2, etc.) does not change this:
ConPTY sits between Alacritty and the child regardless.

Consequences:

- Shift+Enter: works via `ESC + CR` (Meta+Return), which Claude Code
  interprets as a newline. A lone ESC survives ConPTY.
- Mouse scroll in tmux: does not work. Use keyboard copy-mode instead:
  `prefix+[`, then `k`/`j`, `PgUp`/`PgDn`, `Ctrl+u`/`Ctrl+d`; `q` to
  exit.

## WezTerm in this stack

WezTerm ships a built-in SSH client (`wezterm ssh` and `ssh_domains`)
that implements SSH in-process via libssh. No child console process is
spawned, so ConPTY is not in the chain:

```
WezTerm (Windows)  ──libssh──▶  sshd on VM  ──▶  bash → tmux → Claude Code
```

Consequences:

- Shift+Enter: works. `ESC + CR` is used here for consistency; CSI-u
  would also work.
- Mouse scroll in tmux: works. Wheel events reach tmux, which routes
  them to the active pane's copy-mode.

Mintty (from MSYS2 / Git-Bash) with Cygwin's `ssh` is a separate route
to the same result: mintty does not use ConPTY at all, using Cygwin's
PTY implementation instead.

## Install (WezTerm)

1. Install WezTerm: `winget install wez.wezterm` or from wezfurlong.org.
2. Copy `dotfiles/wezterm.lua` to `%USERPROFILE%\.wezterm.lua`. Merge with
   any font/colors/window preferences; the `keys` binding and the SSH
   notes are the load-bearing parts.
3. Copy `dotfiles/.tmux.conf` to `~/.tmux.conf` on the VM, or merge its
   lines into an existing config.
4. Connect with `wezterm ssh user@vm`, or uncomment the `ssh_domains`
   + `default_domain` block in `wezterm.lua` to auto-connect on launch.
5. Install Claude Code. Do not run `/terminal-setup`; it writes the
   CSI-u binding for Shift+Enter, which does not survive ConPTY.

Verification: in a WezTerm SSH session, `showkey -a` + Shift+Enter
prints `^[ 27` then `^M 13`. Mouse wheel inside a tmux pane scrolls that
pane only.

## Install (Alacritty fallback)

Mouse scroll in tmux will not work; keyboard copy-mode is the only way
to scroll.

1. Copy `dotfiles/alacritty.toml` to `%APPDATA%\alacritty\alacritty.toml`.
   Merge with font/colors; the `[[keyboard.bindings]]` block is required.
2. Fully close all Alacritty windows and reopen. Config is read on
   startup only.
3. Copy `dotfiles/.tmux.conf` to `~/.tmux.conf`. `set -g mouse on` is a
   no-op in this path but is harmless.

Requires Alacritty 0.13+ (TOML config; tested on 0.17.0). Alacritty 0.13+
uses winit's key names, so `key = "Enter"` is correct; `"Return"` (seen
in older guides) is not recognized on Windows.

Verification: `showkey -a` + Shift+Enter → `^[ 27` then `^M 13`.

## Troubleshooting

**Shift+Enter produces nothing.** Wrong config path, or the config did
not load. WezTerm auto-reloads but a new window forces it. Alacritty
only reads config at startup — close all windows. Confirm bytes arrive
via `showkey -a`.

**Stale tmux S-Enter binding from a CSI-u guide.**
`tmux list-keys -T root | grep -i s-enter`. If a binding exists:
`tmux unbind-key -T root S-Enter`.

**`cat -v` shows nothing when Shift+Enter is pressed.** `cat -v` is
line-buffered. Press regular Enter to flush; `^[^M` appears.

**Mouse scroll inside tmux does not work under WezTerm.** Check
`tmux show-options -g mouse` — should show `on`. Also confirm the SSH
connection uses WezTerm's built-in client (`wezterm ssh ...` or
`ssh_domains`), not `ssh.exe` invoked as a command inside WezTerm. The
latter goes through ConPTY with the same limitations as Alacritty.

## References

- [Claude Code terminal docs](https://code.claude.com/docs/en/terminal-config)
- [claude-code#26629 — Shift+Enter in tmux](https://github.com/anthropics/claude-code/issues/26629)
- [winit NamedKey enum](https://docs.rs/winit/latest/winit/keyboard/enum.NamedKey.html) — Alacritty 0.13+ key names
- [WezTerm SSH domain](https://wezfurlong.org/wezterm/config/lua/SshDomain.html)
