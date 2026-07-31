#!/usr/bin/env zsh

source "${0:A:h}/helper.zsh"
test_setup
trap 'test_teardown' EXIT

export HISTDB_FILE="${TEST_TMP}/history.db"
export HISTDB_HOST='recording-host'
command mkdir -p -- "${TEST_TMP}/project"
builtin cd -- "${TEST_TMP}/project"
source "${TEST_ROOT}/sqlite-history.zsh"

_histdb_addhistory $'printf \'hello\'\n' || fail 'could not record history'
false
_histdb_update_outcome || fail 'could not record command outcome'
_histdb_addhistory $'ls\n' || fail 'ignored command returned failure'
_histdb_flush || fail 'could not flush history writes'

assert_equal 1 "$(_histdb_query 'select count(*) from history;')" 'recorded row count'
assert_equal "printf 'hello'" "$(_histdb_query 'select argv from commands;')" 'recorded command'
assert_equal "$PWD" "$(_histdb_query 'select dir from places;')" 'recorded directory'
assert_equal recording-host "$(_histdb_query 'select host from places;')" 'recorded host'
assert_equal 1 "$(_histdb_query 'select exit_status from history;')" 'recorded exit status'

_histdb_stop_sqlite_pipe
