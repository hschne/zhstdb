#!/usr/bin/env zsh

source "${0:A:h}/helper.zsh"
test_setup
trap 'test_teardown' EXIT

local help_database="${TEST_TMP}/help.db"
HOME="$HOME" HISTDB_FILE="$help_database" zsh -f -c 'source "$1/sqlite-history.zsh" && histdb --help >/dev/null' zsh "$TEST_ROOT" || fail 'help command failed'
[[ ! -e "$help_database" ]] || fail 'help command created a database'

export HISTDB_FILE="${TEST_TMP}/empty.db"
export HISTDB_HOST='test-host'
command touch "$HISTDB_FILE"
source "${TEST_ROOT}/sqlite-history.zsh"

_histdb_init || fail 'initialization failed for an empty database file'
assert_equal 2 "$(_histdb_query 'pragma user_version;')" 'schema version'
assert_equal 'commands history places' "$(_histdb_query "select name from sqlite_master where type = 'table' and name in ('commands', 'places', 'history') order by name;" | sort | tr '\n' ' ' | sed 's/ $//')" 'schema tables'
assert_equal 0 "$HISTDB_SESSION" 'first session number'

assert_equal 42 "$(_histdb_query 'select 42;')" 'successful query output'
if _histdb_query 'select from invalid' >/dev/null 2>&1; then
    fail 'invalid SQL returned success'
fi

_histdb_stop_sqlite_pipe
assert_equal '' "$HISTDB_FD" 'pipe descriptor after shutdown'
assert_equal '' "$HISTDB_SQLITE_PID" 'sqlite pid after shutdown'

HISTDB_FILE="${TEST_TMP}/legacy.db"
command sqlite3 "$HISTDB_FILE" 'create table commands(id integer);'
if _histdb_init >/dev/null 2>&1; then
    fail 'unsupported schema returned success'
fi
assert_equal '' "$HISTDB_FD" 'unsupported schema started a writer'
