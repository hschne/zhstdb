#!/usr/bin/env zsh

source "${0:A:h}/helper.zsh"
test_setup
trap 'test_teardown' EXIT

local database="${TEST_TMP}/history.db"
local backend="${TEST_ROOT}/histdb-fzf-backend.zsh"
create_histdb "$database"
command sqlite3 "$database" <<'SQL'
insert into commands(id, argv) values
    (1, 'echo success'),
    (2, 'echo failure'),
    (3, 'echo unknown'),
    (4, 'echo sibling');
insert into places(id, host, dir) values
    (1, 'test-host', '/work/project'),
    (2, 'test-host', '/work/project/sub'),
    (3, 'test-host', '/work/project-other');
insert into history(id, session, command_id, place_id, exit_status, start_time, duration) values
    (1, 1, 1, 1, 0, 100, 1),
    (2, 1, 2, 1, 7, 200, 62),
    (3, 1, 3, 2, null, 300, null),
    (4, 1, 4, 3, 0, 400, 1);
SQL

run_backend() {
    HISTDB_FILE="$database" \
        HISTDB_FZF_CWD=/work/project \
        HISTDB_FZF_HOST=test-host \
        zsh -f "$backend" "$@"
}

local output
output="$(run_backend query global)" || fail 'global FZF query failed'
assert_contains "$output" '✓' 'success marker'
assert_contains "$output" '✗' 'failure marker'
assert_contains "$output" '…' 'unknown marker'
assert_not_contains "$output" $'\e' 'ANSI escape leaked into query output'

output="$(run_backend query in)" || fail 'tree FZF query failed'
assert_contains "$output" 'echo success' 'tree omitted exact directory'
assert_contains "$output" 'echo unknown' 'tree omitted child directory'
assert_not_contains "$output" 'echo sibling' 'tree included a sibling prefix'

assert_equal 'echo failure' "$(run_backend command 2)" 'command lookup'
assert_equal '/work/project' "$(run_backend directory 2)" 'directory lookup'

output="$(run_backend preview 2)" || fail 'preview failed'
assert_contains "$output" '7 (failure)' 'preview status'
assert_contains "$output" '1m 2s' 'preview duration'
assert_contains "$output" 'Runs' 'preview run count'

if run_backend command invalid >/dev/null 2>&1; then
    fail 'invalid FZF history id returned success'
fi
if run_backend query invalid >/dev/null 2>&1; then
    fail 'invalid FZF scope returned success'
fi
