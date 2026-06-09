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
running on the dev VM. The hook was extended here with secret-path guards and a
`wget` deny; `settings.json` diverged substantially (see the decision log). The
upstream clone is reference only — not a push target.

## The model: two independent layers

A Bash command passes through two gates that answer *different* questions:

1. **Permission layer** — *"Should this run, and do I get prompted first?"*
   `settings.json` `allow`/`deny` + the PreToolUse hook. Decisions: **allow / ask / deny**.
2. **Sandbox execution layer** — *"Once it runs, what can it actually touch?"*
   The OS jail: `bwrap` (filesystem/process isolation), `socat` (network proxy),
   optional seccomp. It doesn't prompt — it makes operations succeed or fail.

The key consequence: **a permission `allow` is not a capability.** Allowing
`curl` only means "run it without prompting"; the sandbox independently decides
what `curl` can reach. An allowed `curl https://not-allowlisted.example` still
fails at the network layer.

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

Splits compound commands (`&&`, `||`, `;`, `|`, `$()`) into subcommands and
checks each against the pattern lists. Three outcomes:

- **`deny` (hard block, not approvable)** — `BLOCK_PATTERNS`: GitHub repo
  administration the agent must never do on its own — `gh repo edit/delete/archive`,
  `gh secret`, mutating `gh api` (`-X POST/PUT/PATCH/DELETE`). Run these yourself
  with `!<cmd>`.
- **`ask` (prompt, still approvable)** — ~90 destructive patterns (`rm -r`,
  `sudo`, force push, `git reset --hard`, vault/cloud deletes, DB drops,
  `curl | sh`, secret-path access, `ssh`/`scp`, `wget`, `curl -X POST`, `eval`,
  `npx`, …) plus the remote/issue guardrails below.
- **silent** — everything else falls through (the hook never emits `allow`; a
  non-matching command is approved by Layer 1 / the sandbox, not by the hook).

**`gh` is issue-only / `git` remote is read-only** (added 2026-06-09):

- `gh issue …` runs silently; `gh issue delete` and any non-issue `gh` (`pr`,
  `release`, read-only `gh api`, …) → `ask`; the admin set above → `deny`.
- `git push` / `git pull` → `ask` (you sync by hand); `git fetch` and read-only
  remote inspection (`git remote -v`, `git ls-remote`, `git log @{u}`) stay silent.

### Layer 3 — OS sandbox (Linux)

Kernel-level enforcement, independent of the permission grants above:

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

- `enabled: true` — the jail is on.
- `autoAllowBashIfSandboxed: true` — **see decision log**. Commands the sandbox
  fully contains run without a prompt.
- `allowUnsandboxedCommands: true` — a command that can't be sandboxed may fall
  back to running outside the jail, **with a prompt**. (This is the one prompted
  "door" in the wall: a blocked-host `curl` can still be re-run unsandboxed if you
  approve. Set to `false` for no door.)
- `excludedCommands: ["gh:*", "op:*", "pyenv:*"]` — bypass the sandbox entirely,
  by design (they need the real env: gh's token, 1Password's agent, pyenv's shell
  mutation). The `:*` form is a **prefix** match (`gh`, `gh issue list …`); a bare
  name matches *exactly* and would only exempt `gh` with no args.
- `network.allowedDomains` — the allowlist (github, npm, pypi, anthropic, google,
  brew, ghcr, 1password). `WebFetch(domain:…)` allow rules are merged in too.

## What's gated / blocked / impossible

- **Gated (prompts you can approve):** hook deny-pattern matches; escaping the
  sandbox (write outside cwd, hit a non-allowlisted host); claude.ai MCP tools.
- **Blocked outright (no override):** Read/Edit of the deny-listed secret files;
  the same paths are also unreadable inside the sandbox even via shell.
- **Impossible while sandboxed (capability walls):** reaching a non-allowlisted
  host, writing outside the allowed dirs, reading secret paths. Escapable only
  via the prompted unsandboxed-fallback door, or `dangerouslyDisableSandbox`
  (also prompted).

## Decision log

### 2026-06-09 — `autoAllowBashIfSandboxed: false → true`

**Symptom.** Nearly every Bash command (even read-only `grep`/`find`) prompted
for approval. The project's `settings.local.json` had accumulated dozens of
hyper-specific one-off `Bash(grep …)` / `Bash(find …)` "don't ask again" entries
papering over it.

**Root cause.** Two things compounded:
1. The hook was *designed* to auto-approve everything not on its deny-list, but
   was never wired to emit `permissionDecision: "allow"` — it only emits `"ask"`
   or nothing. A silent hook doesn't approve.
2. With `autoAllowBashIfSandboxed: false`, being sandboxed bought no prompt-free
   pass either. So safe commands fell through both and prompted.

**Decision.** Make the **sandbox** the trust boundary for silent execution: flip
`autoAllowBashIfSandboxed` to `true`. Anything the sandbox fully contains runs
without a prompt; anything that needs to *leave* the sandbox (write outside cwd,
new network host) still prompts via `allowUnsandboxedCommands: true`; the hook
stays as the deny-tripwire, forcing `"ask"` on destructive patterns **even when
sandboxed** (e.g. `rm -rf` inside the jail still prompts). Sandbox = "can't hurt
the system"; hook = "ask before destructive-even-if-contained."

**Rationale.** The sandbox is a hard capability wall; the deny-regex is a
heuristic with gaps. "Silent if contained" is a sounder rule than "silent if my
pattern list didn't catch it." One boolean, fully reversible.

**Alternative rejected.** Finishing the hook to emit `"allow"` on non-matches
(realizing its documented intent) — rejected as broader (it would also silently
approve *unsandboxed-fallback* commands) and as adding untested allow-logic when
a one-line flag does the job. The hook keeps earning its place untouched.

**Caveat to watch.** Assumes the hook's `"ask"` still wins over the sandbox
auto-allow (PreToolUse hook decisions should take precedence). If a destructive
command ever stopped prompting, that assumption broke — revisit immediately.

### 2026-06-09 — hook was a silent no-op (input-key bug, fixed) + `gh`/`git` guardrails

**Found while adding the guardrails below.** The hook read the command from
`data['input']['command']`, but Claude Code sends it under
`data['tool_input']['command']`. So `command` was always empty, the hook exited
at `if not command.strip()`, and **Layer 2 never fired** — every destructive
pattern (`rm -rf`, force-push, `curl | sh`, secret-via-shell) went unchecked.
`test-hook.sh` "passed" only because it fed the same wrong `input` key.

Fixed to read `tool_input` (falling back to `input`), verified live with a
captured payload. This was urgent: the autoAllow flip above makes the hook the
**only** tripwire on sandboxed destructive commands, so a dead hook + autoAllow
would have silently auto-approved `rm -rf` in the working tree.

**Guardrails added (the session's request).** `gh` restricted to issue ops;
`git` remote made read-only (see Layer 2). Repo administration is now a hard
`deny` — prompted by the agent having flipped this repo's visibility *unasked*
earlier in the same session. That class of action is now off-limits in config,
not merely by intent.
