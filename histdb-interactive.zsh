typeset -g HISTDB_FZF_FILE="${(%):-%N}"

_histdb_fzf_sql_escape() {
    print -r -- "${${1//\'/\'\'}//$'\x00'}"
}

_histdb_fzf_query() {
    local scope="${1:-global}"
    local db="${HISTDB_FILE:-${HOME}/.histdb/zsh-history.db}"
    local cwd="${HISTDB_FZF_CWD:-${PWD}}"
    local host="${HISTDB_FZF_HOST:-${HOST}}"
    local separator=$'\x1f'

    [[ -f "$db" ]] || return 0

    local cwd_sql="$(_histdb_fzf_sql_escape "$cwd")"
    local host_sql="$(_histdb_fzf_sql_escape "$host")"
    local home_sql="$(_histdb_fzf_sql_escape "$HOME")"
    local scope_where=""

    case "$scope" in
        at)
            scope_where="and places.dir = '${cwd_sql}'"
            ;;
        in)
            if [[ "$cwd" == / ]]; then
                scope_where="and substr(places.dir, 1, 1) = '/'"
            else
                scope_where="and (places.dir = '${cwd_sql}' or substr(places.dir, 1, length('${cwd_sql}') + 1) = '${cwd_sql}/')"
            fi
            ;;
        global)
            ;;
        *)
            print -u2 -- "unknown histdb fzf scope: ${scope}"
            return 1
            ;;
    esac

    sqlite3 -batch -noheader -cmd ".timeout 1000" -separator "$separator" "$db" "
with ranked as (
    select
        history.id,
        history.exit_status,
        history.start_time,
        history.duration,
        commands.argv,
        places.dir,
        row_number() over (
            partition by history.command_id, history.place_id
            order by history.start_time desc, history.id desc
        ) as row_rank
    from history
    join commands on history.command_id = commands.id
    join places on history.place_id = places.id
    where places.host = '${host_sql}'
    ${scope_where}
)
select
    id,
    case
        when exit_status is null or exit_status < 0 then char(27) || '[2m…' || char(27) || '[0m  '
        when exit_status = 0 then char(27) || '[32m✓' || char(27) || '[0m  '
        else char(27) || '[31m✗' || char(27) || '[0m  '
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
        when dir = '${home_sql}' then '~'
        when substr(dir, 1, length('${home_sql}') + 1) = '${home_sql}/' then '~' || substr(dir, length('${home_sql}') + 1)
        else dir
    end || '  ',
    replace(replace(replace(replace(argv, char(27), ''), char(31), ' '), char(10), ' ↩ '), char(9), ' ')
from ranked
where row_rank = 1
order by start_time desc, id desc
"
}

_histdb_fzf_command() {
    local id="$1"
    local db="${HISTDB_FILE:-${HOME}/.histdb/zsh-history.db}"

    [[ "$id" == <-> ]] || return 1
    sqlite3 -batch -noheader -cmd ".timeout 1000" "$db" "
select commands.argv
from history
join commands on history.command_id = commands.id
where history.id = ${id}
limit 1
"
}

_histdb_fzf_directory() {
    local id="$1"
    local db="${HISTDB_FILE:-${HOME}/.histdb/zsh-history.db}"

    [[ "$id" == <-> ]] || return 1
    sqlite3 -batch -noheader -cmd ".timeout 1000" "$db" "
select places.dir
from history
join places on history.place_id = places.id
where history.id = ${id}
limit 1
"
}

_histdb_fzf_format_duration() {
    local duration="$1"

    if [[ -z "$duration" ]]; then
        print -r -- '—'
    elif (( duration >= 60 )); then
        printf '%dm %ds\n' $(( duration / 60 )) $(( duration % 60 ))
    else
        printf '%ds\n' "$duration"
    fi
}

_histdb_fzf_preview() {
    local id="$1"
    local db="${HISTDB_FILE:-${HOME}/.histdb/zsh-history.db}"
    local separator=$'\x1f'

    [[ "$id" == <-> ]] || return 1

    local result="$(sqlite3 -batch -noheader -cmd ".timeout 1000" -separator "$separator" "$db" "
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
limit 1
")"
    local -a fields
    fields=("${(@ps:\x1f:)result}")
    (( ${#fields} >= 6 )) || return 1

    local status_text
    if [[ -z "${fields[1]}" ]] || (( fields[1] < 0 )); then
        status_text='unknown'
    elif [[ "${fields[1]}" == 0 ]]; then
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

if [[ "$ZSH_EVAL_CONTEXT" == toplevel ]]; then
    case "${1:-}" in
        query)
            _histdb_fzf_query "${2:-global}"
            ;;
        preview)
            _histdb_fzf_preview "${2:-}"
            ;;
        command)
            _histdb_fzf_command "${2:-}"
            ;;
        directory)
            _histdb_fzf_directory "${2:-}"
            ;;
        *)
            print -u2 -- 'usage: histdb-interactive.zsh {query SCOPE|preview ID|command ID|directory ID}'
            exit 1
            ;;
    esac
    exit
fi

histdb-fzf-widget() {
    emulate -L zsh
    setopt localoptions pipefail no_aliases

    _histdb_init

    local helper="${HISTDB_FZF_FILE:A}"
    local environment="HISTDB_FILE=${(q)HISTDB_FILE} HISTDB_FZF_CWD=${(q)PWD} HISTDB_FZF_HOST=${(q)HOST}"
    local backend="env ${environment} zsh ${(q)helper}"
    local shortcuts='Alt-A at · Alt-I in · Alt-G global · Alt-J jump · Ctrl-R sort · Ctrl-/ preview'
    local header_at="scope: at · ${shortcuts}"
    local header_in="scope: in · ${shortcuts}"
    local header_global="scope: global · ${shortcuts}"
    local -a fzf_command

    if (( ${+functions[__fzfcmd]} )); then
        fzf_command=(${(z)"$(__fzfcmd)"})
    else
        fzf_command=(fzf)
    fi

    local output
    output="$(_histdb_fzf_query global |
        FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS-} ${FZF_CTRL_R_OPTS-}" "${fzf_command[@]}" \
            --ansi \
            --delimiter=$'\x1f' \
            --with-nth=2.. \
            --nth=4 \
            --scheme=history \
            --tiebreak=index \
            --no-multi \
            --no-hscroll \
            --highlight-line \
            --query="$LBUFFER" \
            --expect=enter,alt-j \
            --header="$header_global" \
            --preview="${backend} preview {1}" \
            --preview-window=up:6:wrap \
            --bind='ctrl-r:toggle-sort' \
            --bind='ctrl-/:toggle-preview' \
            --bind="alt-a:reload(${backend} query at)+change-header(${header_at})" \
            --bind="alt-i:reload(${backend} query in)+change-header(${header_in})" \
            --bind="alt-g:reload(${backend} query global)+change-header(${header_global})"
    )"
    local result=$?
    (( result == 0 )) || return 0

    local -a lines
    lines=("${(@f)output}")
    (( ${#lines} >= 2 )) || return 0

    local key="${lines[1]}"
    local selected="${lines[2]}"
    local id="${selected%%$'\x1f'*}"
    [[ "$id" == <-> ]] || return 0

    local command="$(_histdb_fzf_command "$id")"
    [[ -n "$command" ]] || return 0

    if [[ "$key" == alt-j ]]; then
        local directory="$(_histdb_fzf_directory "$id")"
        if [[ -d "$directory" ]]; then
            builtin cd -- "$directory"
        else
            zle -M "History directory no longer exists: ${directory}"
        fi
    fi

    BUFFER="$command"
    CURSOR=${#BUFFER}
    zle reset-prompt
}

if [[ -o interactive ]]; then
    zle -N histdb-fzf-widget
fi
