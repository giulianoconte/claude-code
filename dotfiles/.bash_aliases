# Slay the Spire 2 dev
_cdslay() {
    # A trailing `claude` arg means: cd, then launch claude there.
    local launch=
    if [ "${!#}" = claude ]; then
        launch=1
        set -- "${@:1:$#-1}"
    fi
    if [ -z "$1" ]; then
        cd "$HOME/dev/sts2" || return
    else
        cd "$HOME/dev/sts2/$1" || return
    fi
    [ -n "$launch" ] && claude
}
alias cdslay='_cdslay'
_cdslay_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=( $(cd "$HOME/dev/sts2" 2>/dev/null && compgen -d -- "$cur") )
    COMPREPLY+=( $(compgen -W claude -- "$cur") )
}
complete -F _cdslay_complete cdslay
alias cdstory='cd "$HOME/dev/sts2/sts2-docs/date-the-spire/tools/story-graph"'
alias sts='touch /media/sf_sts2-mods/.launch-sts2'
alias copylog='cp /media/sf_sts2-appdata/logs/godot.log ~/dev/sts2/sts2-docs/godot0.log'
alias copylog1='cp /media/sf_sts2-appdata/logs/godot.log ~/dev/sts2/sts2-docs/godot1.log'
alias copylog2='cp /media/sf_sts2-appdata/logs/godot.log ~/dev/sts2/sts2-docs/godot2.log'
alias copylog3='cp /media/sf_sts2-appdata/logs/godot.log ~/dev/sts2/sts2-docs/godot3.log'
# SlayTheStats
alias deploy1='~/dev/sts2/slay-the-stats/deploy.sh'
alias deploy2='~/dev/sts2/alt-slay-the-stats/deploy.sh'
alias redeploy1='~/dev/sts2/slay-the-stats/deploy.sh && touch /media/sf_sts2-mods/.launch-sts2'
alias redeploy2='~/dev/sts2/alt-slay-the-stats/deploy.sh && touch /media/sf_sts2-mods/.launch-sts2'
copyrelease() { cp ~/dev/sts2/slay-the-stats/SlayTheStats-$1.zip /media/sf_sts2-mods; }

_tmuxstart() {
    # Optional session name (default "dev"), so `tms foo` builds the same
    # layout in a throwaway session for testing without touching "dev".
    local sess="${1:-dev}"

    # If already inside the target session, do nothing.
    if [ -n "$TMUX" ] && [ "$(tmux display-message -p '#S')" = "$sess" ]; then
        echo "Already inside tmux session '$sess'"
        return 0
    fi

    # Create session if it doesn't exist
    if ! tmux has-session -t "$sess" 2>/dev/null; then
        # Pane sizes are percentages (split-window -l N%), not absolute cells,
        # so the proportions survive terminal resizes — tmux applies each % to
        # the live window size. -l sizes the NEW pane, so an -l 78% split leaves
        # a ~22% top. Panes are targeted by stable id (%N, via -P -F) rather
        # than positional indices, which renumber as panes split.
        local lcol rcol

        # Window 1 "mods": 4 panes. Two columns (~50/50); the left column gets a
        # short top (~22%) over a tall bottom; the right column splits ~50/50.
        tmux new-session -d -s "$sess" -n mods
        lcol=$(tmux display-message -p -t "$sess":mods '#{pane_id}')
        rcol=$(tmux split-window -h -l 50% -P -F '#{pane_id}' -t "$lcol")  # left | right
        tmux split-window -v -l 78% -t "$lcol"   # left  -> top ~22% / bottom ~78%
        tmux split-window -v -l 50% -t "$rcol"   # right -> ~50/50
        tmux select-pane -t "$lcol"              # focus top-left

        # Window 2 "leftoff": 3 panes. Narrow left column (~40%, single full-
        # height pane) | wider right column split ~50/50.
        tmux new-window -t "$sess" -n leftoff
        lcol=$(tmux display-message -p -t "$sess":leftoff '#{pane_id}')
        rcol=$(tmux split-window -h -l 60% -P -F '#{pane_id}' -t "$lcol")  # left ~40% | right ~60%
        tmux split-window -v -l 50% -t "$rcol"   # right -> ~50/50
        tmux select-pane -t "$lcol"              # focus left

        # Window 3 "gh-tracking": 2 panes, same ~40/60 column split, no rows.
        tmux new-window -t "$sess" -n gh-tracking
        lcol=$(tmux display-message -p -t "$sess":gh-tracking '#{pane_id}')
        tmux split-window -h -l 60% -t "$lcol"   # left ~40% | right ~60%
        tmux select-pane -t "$lcol"              # focus left

        tmux select-window -t "$sess":mods       # start on window 1
    else
        echo "Session '$sess' already exists"
    fi

    # Inside tmux, nested attach is refused — switch the client instead
    # (leaves the current session running in the background).
    if [ -n "$TMUX" ]; then
        tmux switch-client -t "$sess"
    else
        tmux attach -t "$sess"
    fi
}
alias tms='_tmuxstart'

alias tmuxtut='less ~/misc/tmux-tutorial.txt'

alias bigloop='seq 100'

# cd into a mod project under ~/dev/sts2, stage everything, commit using its `commit` file.
# Does NOT push — push manually after reviewing.
_gcommit() {
    if [ -z "$1" ]; then
        echo "Usage: gcommit <mod-folder>" >&2
        return 1
    fi
    local target="$HOME/dev/sts2/$1"
    if [ ! -d "$target" ]; then
        echo "Not a directory: $target" >&2
        return 1
    fi
    cd "$target" || return 1
    if [ ! -f commit ]; then
        echo "No 'commit' file in $target" >&2
        return 1
    fi
    local age=$(( $(date +%s) - $(stat -c %Y commit) ))
    if [ "$age" -gt 86400 ]; then
        echo "commit file is $((age / 3600))h old (>24h) — aborting. Update or remove it first." >&2
        return 1
    fi
    git add -A && git commit -F commit && git log --oneline -3
}
alias gcommit='_gcommit'

_gcommit_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}" dirs=() d
    for d in "$HOME/dev/sts2"/*/; do
        [ -d "${d}.git" ] && dirs+=("$(basename "$d")")
    done
    COMPREPLY=( $(compgen -W "${dirs[*]}" -- "$cur") )
}
complete -F _gcommit_complete gcommit

# Add this line to ~/.bashrc, then: source ~/.bashrc

