emulate -LR zsh
setopt no_unset pipe_fail

readonly TEST_ROOT="${0:A:h:h}"
typeset -g TEST_TMP=""

test_setup() {
    TEST_TMP="$(mktemp -d)" || return 1
    export HOME="${TEST_TMP}/home"
    command mkdir -p -- "$HOME"
}

test_teardown() {
    command rm -rf -- "$TEST_TMP"
}

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

assert_equal() {
    local expected="$1"
    local actual="$2"
    local context="${3:-values differ}"

    [[ "$actual" == "$expected" ]] || fail "${context}\nexpected: ${(qqq)expected}\n  actual: ${(qqq)actual}"
}

assert_contains() {
    local value="$1"
    local expected="$2"
    local context="${3:-missing value}"

    [[ "$value" == *"$expected"* ]] || fail "${context}: ${(qqq)expected}"
}

assert_not_contains() {
    local value="$1"
    local unexpected="$2"
    local context="${3:-unexpected value}"

    [[ "$value" != *"$unexpected"* ]] || fail "${context}: ${(qqq)unexpected}"
}

create_histdb() {
    local database="$1"

    command mkdir -p -- "${database:h}"
    command sqlite3 "$database" <<'SQL'
create table commands (
    id integer primary key autoincrement,
    argv text,
    unique(argv) on conflict ignore
);
create table places (
    id integer primary key autoincrement,
    host text,
    dir text,
    unique(host, dir) on conflict ignore
);
create table history (
    id integer primary key autoincrement,
    session integer,
    command_id integer references commands(id),
    place_id integer references places(id),
    exit_status integer,
    start_time integer,
    duration integer
);
pragma user_version = 2;
SQL
}
