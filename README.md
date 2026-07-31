# ZSH History Database

## Overview

`zsh-histdb` stores shell history in SQLite. Each entry records:

- Command text
- Working directory
- Hostname
- Shell session
- Start time and duration
- Exit status

The plugin also provides a query command and an FZF-backed ZLE widget.

## Requirements

- Zsh
- SQLite
- `column` and `iconv` for tabulated query output
- FZF for interactive history search

## Installation

Clone the repository and source the plugin from `.zshrc`:

```zsh
git clone https://github.com/hschne/zsh-histdb \
    "$HOME/.oh-my-zsh/custom/plugins/zsh-histdb"
source "$HOME/.oh-my-zsh/custom/plugins/zsh-histdb/zsh-histdb.plugin.zsh"
```

The plugin works without Oh My Zsh; place it anywhere and source
`zsh-histdb.plugin.zsh`.

For systems without `column`, configure another command that accepts
unit-separator-delimited input:

```zsh
HISTDB_TABULATE_CMD=(sed -e $'s/\x1f/\t/g')
```

## Configuration

- `HISTDB_FILE` sets the database path. The default is
  `$HOME/.histdb/zsh-history.db`.
- `HISTDB_HOST` overrides the hostname stored with new entries.
- `HISTDB_TABULATE_CMD` controls table formatting.
- `HISTORY_IGNORE` is a Zsh glob for commands that should not be recorded.
- `HISTDB_IGNORE_PATTERNS` contains regular expressions for uninteresting
  commands. It defaults to common navigation and monitoring commands.

Set configuration variables before sourcing the plugin.

## Querying history

Run `histdb` to query history for the current host:

```text
histdb git status
histdb --in "$HOME/Source"
histdb --at "$PWD"
histdb --from today --status error
histdb --desc --limit 100
histdb --detail
```

Terms are matched as a substring. Use `*` for a wildcard or `--exact` to
match the complete command. Run `histdb --help` for all options.

`--in` matches the selected directory and its descendants. `--at` matches
only the selected directory.

Use `histdb-top` for frequent commands and `histdb-top dir` for frequent
working directories.

### Forgetting entries

`histdb --forget` displays matching entries and asks before deleting them.
Use `--yes` to skip confirmation:

```text
histdb old-command --forget
histdb --at /removed/project --forget --yes
```

## FZF history search

The plugin defines `histdb-fzf-widget`. Bind it after loading other FZF key
bindings:

```zsh
bindkey -M emacs '^R' histdb-fzf-widget
bindkey -M viins '^R' histdb-fzf-widget
bindkey -M vicmd '^R' histdb-fzf-widget
```

The picker starts with the current command buffer and initially searches the
current directory tree on the current host.

- `M-a`: current directory
- `M-i`: current directory tree
- `M-g`: all directories on the current host
- `M-j`: change to the selected command's directory
- `C-r`: toggle result sorting
- `C-/`: toggle the metadata preview

Selecting a command inserts it into the buffer without executing it.

## Autosuggestions

`zsh-autosuggestions` can query the database through `_histdb_query`:

```zsh
_zsh_autosuggest_strategy_histdb() {
    local command_prefix="$(sql_escape "$1")"
    suggestion="$(_histdb_query "
        select commands.argv
        from history
        join commands on history.command_id = commands.id
        join places on history.place_id = places.id
        where places.host = '$(sql_escape "$HISTDB_HOST")'
          and commands.argv like '${command_prefix}%'
        group by commands.argv
        order by max(history.start_time) desc
        limit 1;
    ")"
}
ZSH_AUTOSUGGEST_STRATEGY=histdb
```

## Database lifecycle

New databases use schema version 2. Unsupported existing schemas fail with an
explicit error; this fork does not migrate old databases.

The database uses WAL mode. This project does not provide database merging or
cross-machine synchronization. Use SQLite-aware backup or replication tooling,
such as Litestream, when needed.

## Development

Install development tools and run the checks:

```sh
mise install
mise run format:check
zsh -n *.zsh tests/*.zsh
zsh -f tests/run.zsh
```

Use `mise run format` to format all Zsh sources with `shfmt` 3.13.0.

Tests use temporary real SQLite databases and a fake FZF adapter. They do not
read or modify the user's history database.
