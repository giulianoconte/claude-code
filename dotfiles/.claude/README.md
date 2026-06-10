# Claude Code permissions & sandbox (Linux)

My live Claude Code permission setup, deployed at `~/.claude/`:

| repo file | lives at |
| --- | --- |
| `settings.json` | `~/.claude/settings.json` |
| `hooks/check-bash-command.sh` | `~/.claude/hooks/check-bash-command.sh` |

These are **plain copies, not symlinks** — same drift caveat as the rest of this
repo (see the top-level README). After editing the live file, copy it back here
and commit.

## Provenance

The three-layer model and the `check-bash-command.sh` hook are adapted from
[dylancaponi/claude-code-permissions](https://github.com/dylancaponi/claude-code-permissions)
(cloned at `~/dev/misc/claude-code-permissions`). That upstream is a **macOS**
setup (its Layer 3 is Seatbelt / `sandbox-exec`); this is the **Linux** version,
running on the dev VM. **Heads-up:** the upstream hook never actually enforced
anything under current Claude Code — it had an input-key bug, an output-schema bug,
and a backtick bug (see the decision log); all three were fixed here. `settings.json`
also diverged substantially. The upstream clone is reference only — not a push target.

## The model: two independent layers

A Bash command passes through two gates that answer *different* questions:

1. **Permission layer** — *"Should this run, and do I get prompted first?"*
   `settings.json` `allow`/`deny` + the PreToolUse hook. Decisions: **allow / ask / deny**.
2. **Sandbox execution layer** — *"Once it runs, what can it actually touch?"*
   The OS jail: `bwrap` (filesystem/process isolation), `socat` (network proxy),
   optional seccomp. It doesn't prompt — it makes operations succeed or fail.
   **Currently disabled (see Layer 3); the permission layer is the active guardrail.**

The key consequence (when the sandbox is on): **a permission `allow` is not a
capability** — allowing `curl` only means "run it without prompting"; the sandbox
independently decides what it can reach. With the sandbox currently **off**, that
second gate is gone: an `allow` runs with full capability, so the hook's deny/ask
list is the only thing in front of a command.

### Layer 1 — permission rules (`settings.json`)

- **allow**: `Read`, `Glob`, `Grep`, `WebSearch`, `WebFetch`, `Task`, `Bash`.
- **deny** (Read **and** Edit) of secret paths: `~/.ssh`, `~/.aws`, `~/.gnupg`,
  `~/.netrc`, `~/.config/gh/hosts.yml`, `~/.kube/config`, `~/.docker/config.json`,
  `~/.npmrc`, `~/.pypirc`, and `.env` / `.env.local` / `.env.*.local`. A `deny`
  is a hard refusal — no "approve anyway" prompt.
- **claude.ai MCP servers** (Gmail / Calendar / Drive) always prompt — nothing
  auto-allowed. (An invalid `mcp__claude_ai_*` allow rule was removed 2026-06-06;
  do not re-add it.)
- Linux glob gotcha: Read/Edit rules use gitignore semantics, and a **leading
  `**/` is silently ignored on Linux**. Use the bare form (`Read(.env)`, matches
  at any depth under cwd) or an anchored form (`Read(~/.ssh/**)`), never a
  leading `**/`.

### Layer 2 — PreToolUse Bash hook (`hooks/check-bash-command.sh`)

The **single authoritative arbiter** for Bash. It splits compound commands
(`&&`, `||`, `;`, `|`, `$()`) into subcommands, checks each against the pattern
lists, and emits an explicit decision for **every** command (`autoAllow` is off,
so the hook always fires — see decision log):

- **`deny` (hard block, not approvable)** — `BLOCK_PATTERNS`: GitHub repo
  administration the agent must never do on its own — `gh repo edit/delete/archive`,
  `gh secret`, mutating `gh api` (`-X POST/PUT/PATCH/DELETE`). Run these yourself
  with `!<cmd>`.
- **`ask` (prompt, still approvable)** — ~90 destructive patterns (`rm -r`,
  `sudo`, force push, `git reset --hard`, vault/cloud deletes, DB drops,
  `curl | sh`, secret-path access, `ssh`/`scp`, `wget`, `curl -X POST`, `eval`,
  `npx`, …) plus the remote/issue guardrails below.
- **`allow` (silent, no prompt)** — everything else. An explicit `allow` is
  emitted so the hook governs even with `autoAllowBashIfSandboxed: false`; the OS
  sandbox (Layer 3) still applies underneath.

**`gh` is issue-only / `git` remote is read-only** (added 2026-06-09):

- `gh issue …` runs silently; **read-only inspection** also silent (`gh repo
  view/list`, `gh pr/release/run/workflow view/list`, `gh pr diff/checks/status`,
  `gh auth status` — an `ALLOW_PATTERNS` tier checked *after* the deny block so it
  can never override it). `gh issue delete` and other non-issue `gh` → `ask`; the
  admin set above (incl. all `gh secret`, even `list`) → `deny`.
- `git push` / `git pull` → `ask` (you sync by hand); `git fetch` and read-only
  remote inspection (`git remote -v`, `git ls-remote`, `git log @{u}`) stay silent.

> **Editing this hook:** the pattern lists live inside `python3 -c "…"`, which is a
> double-quoted *bash* string. **Never put a backtick or `$` in a comment or string
> there** — bash will execute backticks as a command substitution before Python
> runs. (That bug executed `` `gh auth token` `` on every command until fixed.)

### Layer 3 — OS sandbox (Linux) — currently DISABLED

**`sandbox.enabled: false` as of 2026-06-09** (see decision log). The OS sandbox
fought the dev workflow — `dotnet build`, `git status`, and most build/restore
commands can't run contained, so they constantly hit the unsandboxed-fallback
prompt. With it off, the hook (Layer 2) is the sole guardrail and routine dev work
runs prompt-free. The config below is left in place (inert) — flip `enabled` to
`true` to restore it. When enabled it provides kernel-level enforcement,
independent of the permission grants above:

- **`bwrap`** (bubblewrap) — filesystem/process isolation. Writes confined to the
  working dir + `$TMPDIR` + a few sinks; reads broad except the deny list;
  secret paths unreadable even via `cat`.
- **`socat`** — network proxy that enforces `network.allowedDomains`. **Required**
  for the network allowlist to work at all (missing socat → `/doctor` warns and
  the allowlist isn't enforced). Inside the jail, only allowlisted hosts are
  reachable; everything else fails to connect.
- **seccomp** (`@anthropic-ai/sandbox-runtime`, npm `-g`) — optional syscall
  filter (e.g. blocks unix-socket connects). **Not installed** here.

Relevant knobs in `settings.json` → `sandbox`:

- `enabled: false` — **currently off** (see above / decision log); `true` re-enables the jail.
- `autoAllowBashIfSandboxed: false` — **must stay false** (see decision log).
  `true` auto-approves sandboxed commands *and bypasses the PreToolUse hook*,
  silently disabling Layer 2. With it false, the hook fires on every command and
  is authoritative; the sandbox still enforces its boundaries underneath.
- `allowUnsandboxedCommands: true` — a command that can't be sandboxed may fall
  back to running outside the jail, **with a prompt**. (This is the one prompted
  "door" in the wall: a blocked-host `curl` can still be re-run unsandboxed if you
  approve. Set to `false` for no door.)
- `excludedCommands: ["gh:*", "op:*", "pyenv:*"]` — bypass the sandbox entirely,
  by design (they need the real env: gh's token, 1Password's agent, pyenv's shell
  mutation). The `:*` form is a **prefix** match (`gh`, `gh issue list …`); a bare
  name matches *exactly* and would only exempt `gh` with no args. (These still go
  through the hook — confirmed: `gh secret list` is denied.)
- `network.allowedDomains` — the allowlist (github, npm, pypi, anthropic, google,
  brew, ghcr, 1password). `WebFetch(domain:…)` allow rules are merged in too.

## What's gated / blocked (sandbox off — the hook is the guardrail)

- **Gated (prompts you can approve):** hook `ask` matches (`rm -r`, `git push`/`pull`,
  non-issue `gh`, destructive ops); the `Edit` tool; claude.ai MCP tools.
- **Blocked outright (no override):** hook `deny` matches (repo admin); Read/Edit
  of the deny-listed secret files.
- **No longer enforced (sandbox off):** network confinement and filesystem-write
  confinement — a command can now reach any host and write anywhere. The hook's
  deny/ask list is the protection, not an OS capability wall. (Secret *reads* are
  still covered by the Read/Edit denies + the hook's secret-path `ask` guards.)

## Decision log

### 2026-06-09 (later) — disabled the OS sandbox (`sandbox.enabled: false`)

After making the hook authoritative (next entry), the remaining friction was the
sandbox itself: `dotnet build`, `git status`, and most build/restore commands can't
run contained (NuGet/network + writes outside cwd), so each hit the "Bash command
(unsandboxed)" fallback prompt — pervasive across a multi-repo dev workflow. Turned
the sandbox off. The guardrails the user wanted live in the hook (Layer 2), which is
independent of the sandbox and still fully enforces (verified live: safe `grep`
silent, `gh secret` / repo-admin blocked). Trade-off: lose the network/filesystem
capability wall (defense-in-depth vs. a rogue command) — an acceptable trade on a
trusted single-user dev VM for a usable workflow. The sandbox config is left in
place but inert; flip `enabled` back to `true` to restore it.

### 2026-06-09 — make the hook the authoritative arbiter (and fix it; it had never worked)

**Goal.** Stop prompting on safe commands (read-only `grep`/`find`, etc.) without
losing real guardrails. `settings.local.json` had bloated with dozens of one-off
`Bash(grep …)` "don't ask again" approvals papering over the prompts.

**False start — `autoAllowBashIfSandboxed: true`.** First tried "trust the
sandbox": flip autoAllow to `true` so contained commands run silently. **That
silently disables the hook** — `autoAllow: true` auto-approves sandboxed commands
and skips the PreToolUse hook entirely, so the deny-list and the new `gh`/`git`
guardrails never fire. Confirmed live (`rm -rf`, `gh secret list` ran with no
prompt, no hook involvement). Reverted to `autoAllowBashIfSandboxed: false`.

**The hook had never actually enforced anything — three bugs, all fixed:**
1. **Input key.** Read `data['input']['command']`; Claude Code sends
   `data['tool_input']['command']`. `command` was always empty → the hook exited
   immediately, checking nothing. (`test-hook.sh` "passed" by feeding the same
   wrong key.) Fixed to read `tool_input` (fallback `input`).
2. **Output schema.** Emitted `{"hookSpecificOutput":{"permissionDecision":…,
   "reason":…}}` — missing the required `"hookEventName":"PreToolUse"` and using
   `reason` instead of `permissionDecisionReason`. Claude Code silently discarded
   every verdict. Fixed to the documented schema.
3. **Backticks in comments.** The Python runs via `python3 -c "…"` (a double-quoted
   *bash* string), so backticked text in comments (e.g. `` `gh auth token` ``) was
   executed by bash as a command substitution on every invocation — crashing the
   hook and leaking the GH token into process args. Removed all backticks.

**Final architecture.** `autoAllowBashIfSandboxed: false` + the hook emits an
explicit `allow`/`ask`/`deny` for *every* command → it always fires and is
authoritative; the OS sandbox (Layer 3) stays as the capability wall underneath.
A hook `allow` suppresses the prompt but the command still runs sandboxed.
**Verified live:** safe `grep` → silent; `rm -rf` → prompt; `gh secret` /
`gh repo edit` → blocked.

**Guardrails (the session's request).** `gh` restricted to issue ops + a read-only
inspection allowlist; `git` remote made read-only (push/pull → ask, fetch silent);
repo administration hard-`deny` — prompted by the agent having flipped this repo's
visibility *unasked* earlier the same session. Off-limits in config now, not just
by intent.
