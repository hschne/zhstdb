#!/usr/bin/env zsh

source "${0:A:h}/helper.zsh"
test_setup
trap 'test_teardown' EXIT

export HISTDB_FILE="${TEST_TMP}/history.db"
export HISTDB_HOST='widget-host'
local project="${TEST_TMP}/project"
command mkdir -p -- "$project"
create_histdb "$HISTDB_FILE"
command sqlite3 "$HISTDB_FILE" <<SQL
insert into commands(id, argv) values (1, 'echo selected');
insert into places(id, host, dir) values (1, 'widget-host', '${project}');
insert into history(id, session, command_id, place_id, exit_status, start_time, duration)
values (1, 1, 1, 1, 0, 100, 1);
SQL

local fake_fzf="${TEST_TMP}/fake-fzf"
cat >"$fake_fzf" <<'ZSH'
#!/usr/bin/env zsh
local input="$(cat)"
local selected="${input%%$'\n'*}"
print -r -- "${HISTDB_TEST_FZF_KEY:-enter}"
print -r -- "$selected"
ZSH
chmod +x "$fake_fzf"

source "${TEST_ROOT}/sqlite-history.zsh"
source "${TEST_ROOT}/histdb-interactive.zsh"

__fzfcmd() {
    print -r -- "$fake_fzf"
}
zle() {
    return 0
}

builtin cd -- "$project"
typeset -g BUFFER='unchanged'
typeset -g LBUFFER='echo'
typeset -g CURSOR=0

histdb-fzf-widget || fail 'FZF widget failed'
assert_equal 'echo selected' "$BUFFER" 'selected command buffer'
assert_equal ${#BUFFER} "$CURSOR" 'selected command cursor'

export HISTDB_TEST_FZF_KEY=alt-j
builtin cd -- "$TEST_TMP"
histdb-fzf-widget || fail 'FZF jump failed'
assert_equal "$project" "$PWD" 'selected command directory'

_histdb_stop_sqlite_pipe
