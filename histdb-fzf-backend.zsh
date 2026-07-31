#!/usr/bin/env zsh

emulate -LR zsh
setopt pipe_fail

_histdb_fzf_escape() {
    print -r -- ${${1//\'/\'\'}//$'\x00'/}
}

_histdb_fzf_sqlite() {
    local separator="$1"
    shift

    command sqlite3 -batch -noheader -cmd '.timeout 1000' -separator "$separator" "$HISTDB_FILE" "$@"
}

_histdb_fzf_query() {
    local scope="${1:-global}"
    local directory="${HISTDB_FZF_CWD:-$PWD}"
    local host="${HISTDB_FZF_HOST:-$HOST}"
    local separator=$'\x1f'
    local scope_condition=""
    local escaped_directory="$(_histdb_fzf_escape "$directory")"
    local escaped_host="$(_histdb_fzf_escape "$host")"
    local escaped_home="$(_histdb_fzf_escape "$HOME")"

    case "$scope" in
        at)
            scope_condition="and places.dir = '${escaped_directory}'"
            ;;
        in)
            if [[ "$directory" == / ]]; then
                scope_condition="and substr(places.dir, 1, 1) = '/'"
            else
                scope_condition="and (places.dir = '${escaped_directory}' or substr(places.dir, 1, length('${escaped_directory}') + 1) = '${escaped_directory}/')"
            fi
            ;;
        global) ;;
        *)
            print -u2 -- "histdb-fzf: unknown scope: $scope"
            return 1
            ;;
    esac

    _histdb_fzf_sqlite "$separator" "
with ranked as (
    select
        history.id,
        history.exit_status,
        history.start_time,
        commands.argv,
        places.dir,
        row_number() over (
            partition by history.command_id, history.place_id
            order by history.start_time desc, history.id desc
        ) as row_rank
    from history
    join commands on history.command_id = commands.id
    join places on history.place_id = places.id
    where places.host = '${escaped_host}'
    ${scope_condition}
)
select
    id,
    case
        when exit_status is null or exit_status < 0 then '…  '
        when exit_status = 0 then '✓  '
        else '✗  '
    end,
    strftime(
        case
            when date(start_time, 'unixepoch', 'localtime') = date('now', 'localtime') then '%H:%M'
            else '%d/%m'
        end,
        start_time,
        'unixepoch',
        'localtime'
    ) || '  ',
    case
        when dir = '${escaped_home}' then '~'
        when substr(dir, 1, length('${escaped_home}') + 1) = '${escaped_home}/'
            then '~' || substr(dir, length('${escaped_home}') + 1)
        else dir
    end || '  ',
    replace(replace(replace(replace(argv, char(27), ''), char(31), ' '), char(10), ' ↩ '), char(9), ' ')
from ranked
where row_rank = 1
order by start_time desc, id desc;
"
}

_histdb_fzf_command() {
    local id="$1"

    [[ "$id" == <-> ]] || {
        print -u2 -- "histdb-fzf: invalid history id: $id"
        return 1
    }

    _histdb_fzf_sqlite $'\x1f' "
select commands.argv
from history
join commands on history.command_id = commands.id
where history.id = ${id}
limit 1;
"
}

_histdb_fzf_directory() {
    local id="$1"

    [[ "$id" == <-> ]] || {
        print -u2 -- "histdb-fzf: invalid history id: $id"
        return 1
    }

    _histdb_fzf_sqlite $'\x1f' "
select places.dir
from history
join places on history.place_id = places.id
where history.id = ${id}
limit 1;
"
}

_histdb_fzf_format_duration() {
    local duration="$1"

    if [[ -z "$duration" ]]; then
        print -r -- '—'
    elif ((duration >= 60)); then
        printf '%dm %ds\n' $((duration / 60)) $((duration % 60))
    else
        printf '%ds\n' "$duration"
    fi
}

_histdb_fzf_preview() {
    local id="$1"
    local separator=$'\x1f'
    local result status_text
    local -a fields

    [[ "$id" == <-> ]] || {
        print -u2 -- "histdb-fzf: invalid history id: $id"
        return 1
    }

    result="$(_histdb_fzf_sqlite "$separator" "
select
    ifnull(history.exit_status, ''),
    datetime(history.start_time, 'unixepoch', 'localtime'),
    ifnull(history.duration, ''),
    replace(replace(places.dir, char(27), ''), char(31), ' '),
    (
        select count(*)
        from history as runs
        where runs.command_id = history.command_id
          and runs.place_id = history.place_id
    ),
    replace(replace(commands.argv, char(27), ''), char(31), ' ')
from history
join commands on history.command_id = commands.id
join places on history.place_id = places.id
where history.id = ${id}
limit 1;
")" || return 1

    fields=("${(@ps:\x1f:)result}")
    ((${#fields} >= 6)) || return 1

    if [[ -z "${fields[1]}" ]] || ((fields[1] < 0)); then
        status_text='unknown'
    elif ((fields[1] == 0)); then
        status_text='0 (success)'
    else
        status_text="${fields[1]} (failure)"
    fi

    print -r -- "${fields[6]}"
    print
    printf '%-10s %s\n' 'Directory' "${fields[4]}"
    printf '%-10s %s\n' 'When' "${fields[2]}"
    printf '%-10s %s\n' 'Status' "$status_text"
    printf '%-10s %s\n' 'Duration' "$(_histdb_fzf_format_duration "${fields[3]}")"
    printf '%-10s %s\n' 'Runs' "${fields[5]}"
}

main() {
    local operation="${1:-}"

    case "$operation" in
        query | preview | command | directory) ;;
        *)
            print -u2 -- 'usage: histdb-fzf-backend.zsh {query SCOPE|preview ID|command ID|directory ID}'
            return 1
            ;;
    esac

    HISTDB_FILE="${HISTDB_FILE:-${HOME}/.histdb/zsh-history.db}"
    [[ -f "$HISTDB_FILE" ]] || return 0

    case "$operation" in
        query) _histdb_fzf_query "${2:-global}" ;;
        preview) _histdb_fzf_preview "${2:-}" ;;
        command) _histdb_fzf_command "${2:-}" ;;
        directory) _histdb_fzf_directory "${2:-}" ;;
    esac
}

main "$@"
