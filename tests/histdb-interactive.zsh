emulate -LR zsh
setopt err_exit no_unset pipe_fail

local root="${0:A:h:h}"
local tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

local db="${tmp}/history.db"
sqlite3 "$db" <<'SQL'
create table commands (id integer primary key, argv text);
create table places (id integer primary key, host text, dir text);
create table history (id integer primary key, session int, command_id int, place_id int, exit_status int, start_time int, duration int);
insert into commands values (1, 'echo success'), (2, 'echo failure'), (3, 'echo unknown');
insert into places values (1, 'testhost', '/work/project');
insert into history values
    (1, 1, 1, 1, 0, 100, 1),
    (2, 1, 2, 1, 7, 200, 2),
    (3, 1, 3, 1, null, 300, 3);
SQL

local output="$(
    HISTDB_FILE="$db" \
    HISTDB_FZF_CWD=/work/project \
    HISTDB_FZF_HOST=testhost \
    zsh "${root}/histdb-interactive.zsh" query global
)"

[[ "$output" == *'✓'* ]]
[[ "$output" == *'✗'* ]]
[[ "$output" == *'…'* ]]
[[ "$output" != *'^[[0m'* ]]
[[ "$output" != *$'\e'* ]]
