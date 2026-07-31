command -v sqlite3 >/dev/null 2>&1 || return 1

zmodload zsh/datetime
zmodload zsh/system
zmodload -F zsh/stat b:zstat

((${+builtins[sysopen]})) || return 1
autoload -Uz add-zsh-hook

if [[ -n ${HISTDB_CORE_LOADED:-} ]]; then
    return 0
fi
typeset -g HISTDB_CORE_LOADED=1

typeset -g HISTDB_ROOT="${0:A:h}"
typeset -g HISTDB_FILE="${HISTDB_FILE:-${HOME}/.histdb/zsh-history.db}"
typeset -g HISTDB_HOST="${HISTDB_HOST:-${HOST}}"
typeset -g HISTDB_SESSION="${HISTDB_SESSION:-}"
typeset -g HISTDB_FD=""
typeset -g HISTDB_SQLITE_PID=""
typeset -ga HISTDB_INODE=()
typeset -g HISTDB_INITIALIZED_FILE=""

if ((!${+HISTDB_IGNORE_PATTERNS})); then
    typeset -ga HISTDB_IGNORE_PATTERNS=(
        '^ls$'
        '^cd$'
        '^ '
        '^histdb'
        '^top$'
        '^htop$'
    )
else
    typeset -ga HISTDB_IGNORE_PATTERNS
fi

if ((!${+HISTDB_TABULATE_CMD})); then
    typeset -ga HISTDB_TABULATE_CMD=(column -t -s $'\x1f')
fi

sql_escape() {
    print -r -- ${${1//\'/\'\'}//$'\x00'/}
}

_histdb_query() {
    command sqlite3 -batch -noheader -cmd '.timeout 1000' "$HISTDB_FILE" "$@"
}

_histdb_stop_sqlite_pipe() {
    local fd="${HISTDB_FD:-}"
    local pid="${HISTDB_SQLITE_PID:-}"

    HISTDB_FD=""
    HISTDB_SQLITE_PID=""
    HISTDB_INODE=()

    if [[ -n "$fd" ]]; then
        eval 'exec {fd}>&-' || true
    fi

    if [[ -n "$pid" ]]; then
        wait "$pid" 2>/dev/null || true
    fi
}

_histdb_start_sqlite_pipe() {
    local pipe_dir pipe
    local -a inode

    [[ -z ${HISTDB_FD:-} ]] || return 0

    pipe_dir="$(mktemp -d)" || return 1
    pipe="${pipe_dir}/sqlite"
    command mkfifo "$pipe" || {
        command rm -rf -- "$pipe_dir"
        return 1
    }

    setopt local_options no_notify no_monitor
    command sqlite3 -batch -noheader "$HISTDB_FILE" <"$pipe" >/dev/null &
    HISTDB_SQLITE_PID=$!

    if ! sysopen -w -o cloexec -u HISTDB_FD -- "$pipe"; then
        kill "$HISTDB_SQLITE_PID" 2>/dev/null || true
        command rm -rf -- "$pipe_dir"
        HISTDB_SQLITE_PID=""
        return 1
    fi

    command rm -rf -- "$pipe_dir"
    zstat -A inode +inode "$HISTDB_FILE" || {
        _histdb_stop_sqlite_pipe
        return 1
    }
    HISTDB_INODE=("${inode[@]}")
}

_histdb_ensure_sqlite_pipe() {
    local -a inode

    zstat -A inode +inode "$HISTDB_FILE" || return 1
    if [[ -z ${HISTDB_FD:-} || "${(j: :)inode}" != "${(j: :)HISTDB_INODE}" ]]; then
        _histdb_stop_sqlite_pipe
        _histdb_start_sqlite_pipe
    fi
}

_histdb_write() {
    _histdb_ensure_sqlite_pipe || return 1
    command cat >&$HISTDB_FD || return 1
    print -r -- ';' >&$HISTDB_FD
}

_histdb_flush() {
    [[ "$HISTDB_INITIALIZED_FILE" == "$HISTDB_FILE" ]] || return 0
    _histdb_stop_sqlite_pipe
    _histdb_start_sqlite_pipe
}

_histdb_create_schema() {
    _histdb_query <<'SQL'
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

_histdb_prepare_schema() {
    local version table_count

    version="$(_histdb_query 'pragma user_version;')" || return 1
    if [[ "$version" == 0 ]]; then
        table_count="$(_histdb_query "select count(*) from sqlite_master where type = 'table' and name in ('commands', 'places', 'history');")" || return 1
        if ((table_count == 0)); then
            _histdb_create_schema || return 1
        else
            print -u2 -- "histdb: unsupported database schema version 0: $HISTDB_FILE"
            return 1
        fi
    elif [[ "$version" != 2 ]]; then
        print -u2 -- "histdb: unsupported database schema version ${version}: $HISTDB_FILE"
        return 1
    fi

    _histdb_query >/dev/null <<'SQL'
create index if not exists hist_time on history(start_time);
create index if not exists place_dir on places(dir);
create index if not exists place_host on places(host);
create index if not exists history_command_place on history(command_id, place_id);
pragma journal_mode = wal;
pragma synchronous = normal;
SQL
}

_histdb_init() {
    local directory escaped_host session

    if [[ "$HISTDB_INITIALIZED_FILE" == "$HISTDB_FILE" ]]; then
        _histdb_ensure_sqlite_pipe
        return
    fi

    _histdb_stop_sqlite_pipe
    directory="${HISTDB_FILE:h}"
    command mkdir -p -- "$directory" || return 1
    _histdb_prepare_schema || return 1

    escaped_host="$(sql_escape "$HISTDB_HOST")"
    session="$(_histdb_query "
select coalesce(max(history.session) + 1, 0)
from history
join places on places.id = history.place_id
where places.host = '${escaped_host}';
")" || return 1

    HISTDB_SESSION="$session"
    HISTDB_INITIALIZED_FILE="$HISTDB_FILE"
    _histdb_start_sqlite_pipe
}

_histdb_update_outcome() {
    local exit_status=$?
    local finished=$EPOCHSECONDS

    [[ "$HISTDB_INITIALIZED_FILE" == "$HISTDB_FILE" ]] || return 0

    _histdb_write <<SQL
update history
set exit_status = ${exit_status},
    duration = ${finished} - start_time
where id = (
    select max(id)
    from history
    where session = ${HISTDB_SESSION}
      and exit_status is null
);
SQL
}

_histdb_addhistory() {
    setopt local_options glob_subst

    local history_line="$1"
    local command_text="${history_line[1,-2]}"
    local pattern escaped_command escaped_directory started

    if [[ -o histignorespace && "$command_text" == ' '* ]]; then
        return 0
    fi
    if [[ -n ${HISTORY_IGNORE:-} && "$command_text" == $HISTORY_IGNORE ]]; then
        return 0
    fi
    for pattern in "${HISTDB_IGNORE_PATTERNS[@]}"; do
        if [[ "$command_text" =~ $pattern ]]; then
            return 0
        fi
    done
    [[ -n "$command_text" ]] || return 0

    _histdb_init || return 1

    escaped_command="$(sql_escape "$command_text")"
    escaped_directory="$(sql_escape "$PWD")"
    started=$EPOCHSECONDS

    _histdb_write <<SQL
insert into commands(argv) values ('${escaped_command}');
insert into places(host, dir) values ('$(sql_escape "$HISTDB_HOST")', '${escaped_directory}');
insert into history(session, command_id, place_id, start_time)
select
    ${HISTDB_SESSION},
    commands.id,
    places.id,
    ${started}
from commands, places
where commands.argv = '${escaped_command}'
  and places.host = '$(sql_escape "$HISTDB_HOST")'
  and places.dir = '${escaped_directory}';
SQL
}

histdb-top() {
    emulate -L zsh
    setopt local_options pipe_fail

    local field label separator=$'\x1f'

    _histdb_init || return 1

    case "${1:-cmd}" in
        cmd)
            field='commands.argv'
            label='cmd'
            ;;
        dir)
            field='places.dir'
            label='dir'
            ;;
        *)
            print -u2 -- 'usage: histdb-top [cmd|dir]'
            return 1
            ;;
    esac

    _histdb_query -separator "$separator" -header "
select count(*) as count,
       places.host,
       replace(${field}, char(10), char(10) || '${separator}${separator}') as ${label}
from history
join commands on history.command_id = commands.id
join places on history.place_id = places.id
group by places.host, ${field}
order by count(*) desc;
" | "${HISTDB_TABULATE_CMD[@]}"
}

add-zsh-hook zshexit _histdb_stop_sqlite_pipe
add-zsh-hook zshaddhistory _histdb_addhistory
add-zsh-hook precmd _histdb_update_outcome

source "${HISTDB_ROOT}/histdb-query.zsh"
