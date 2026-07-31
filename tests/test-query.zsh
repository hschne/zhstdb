#!/usr/bin/env zsh

source "${0:A:h}/helper.zsh"
test_setup
trap 'test_teardown' EXIT

export HISTDB_FILE="${TEST_TMP}/history.db"
export HISTDB_HOST='query-host'
create_histdb "$HISTDB_FILE"
command sqlite3 "$HISTDB_FILE" <<'SQL'
insert into commands(id, argv) values
    (1, 'echo old'),
    (2, 'echo project'),
    (3, 'echo sibling'),
    (4, 'echo remote');
insert into places(id, host, dir) values
    (1, 'query-host', '/foo'),
    (2, 'query-host', '/foo/sub'),
    (3, 'query-host', '/foobar'),
    (4, 'remote-host', '/remote');
insert into history(id, session, command_id, place_id, exit_status, start_time, duration) values
    (1, 1, 1, 1, 0, unixepoch('2024-01-01'), 1),
    (2, 1, 2, 2, 0, unixepoch('2024-01-03'), 2),
    (3, 1, 3, 3, 1, unixepoch('2024-01-04'), 3),
    (4, 2, 2, 2, 7, unixepoch('2024-01-05'), 4),
    (5, 1, 4, 4, 0, unixepoch('2024-01-06'), 5);
SQL

typeset -ga HISTDB_TABULATE_CMD=(cat)
source "${TEST_ROOT}/sqlite-history.zsh"

local output
output="$(histdb-top)" || fail 'top query failed'
assert_contains "$output" 'echo project' 'top query omitted command counts'

output="$(histdb --in /foo --sep '|' --limit 10)" || fail 'tree query failed'
assert_contains "$output" 'echo old' 'tree query omitted exact directory'
assert_contains "$output" 'echo project' 'tree query omitted child directory'
assert_not_contains "$output" 'echo sibling' 'tree query included a sibling prefix'
assert_equal 1 "$(print -r -- "$output" | grep -c 'echo project')" 'duplicate command/place rows were not collapsed'

output="$(histdb --from 2024-01-04 --sep '|' --limit 10)" || fail 'date query failed'
assert_contains "$output" 'echo project' 'date query omitted a recent command'
assert_contains "$output" 'echo sibling' 'date query omitted the threshold date'
assert_not_contains "$output" 'echo old' 'date query included an old command'

output="$(histdb --desc --sep '|' --limit 2)" || fail 'descending query failed'
assert_equal 'echo project echo sibling' "$(print -r -- "$output" | grep '|' | tail -n +2 | cut -d '|' -f 4 | tr '\n' ' ' | sed 's/ $//')" 'descending limited order'

output="$(histdb --host --sep='|' --limit=10)" || fail 'all-host query failed'
assert_contains "$output" '|query-host|' 'all-host query omitted the current host column'
assert_contains "$output" '|remote-host|' 'all-host query omitted remote history'

output="$(histdb --host=remote-host --sep='|' --limit=10)" || fail 'host query failed'
assert_contains "$output" 'echo remote' 'host query omitted remote history'
assert_not_contains "$output" 'echo project' 'host query included current-host history'

output="$(histdb --status=7 --detail --sep='|' --limit=10)" || fail 'status query failed'
assert_contains "$output" 'echo project' 'status query omitted matching history'
assert_contains "$output" '|7|4|echo project' 'detail query omitted status or duration'

if histdb --limit nope >/dev/null 2>&1; then
    fail 'invalid limit returned success'
fi
if histdb --status nope >/dev/null 2>&1; then
    fail 'invalid status returned success'
fi

histdb 'echo old' --exact --forget --yes --sep '|' --limit 10 >/dev/null || fail 'forget query failed'
assert_equal 0 "$(_histdb_query "select count(*) from commands where argv = 'echo old';")" 'forgotten command cleanup'
assert_equal 3 "$(_histdb_query "select count(*) from history join places on history.place_id = places.id where places.host = 'query-host';")" 'forgotten history cleanup'

_histdb_stop_sqlite_pipe
