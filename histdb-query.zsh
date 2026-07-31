_histdb_query_usage() {
    cat <<'EOF'
usage: histdb [terms] [options]

Options:
  --desc        Show newest results first
  --host [host] Show all hosts, or only the given host
  --in [dir]    Restrict results to a directory tree
  --at [dir]    Restrict results to one directory
  -s [session]  Restrict results to a session
  --detail      Show exit status and duration
  --exact       Match terms as a complete command
  --from date   Show commands on or after a date
  --until date  Show commands on or before a date
  --status n    Restrict results to an exit status; "error" means nonzero
  --limit n     Limit results; defaults to one screen
  --sep value   Set the output separator and disable tabulation
  --forget      Delete matching history
  --yes         Skip confirmation when deleting
  -d            Print the generated SQL
  -h, --help    Show this help
EOF
}

_histdb_tree_condition() {
    local directory="$1"
    local escaped="$(sql_escape "$directory")"

    if [[ "$directory" == / ]]; then
        REPLY="substr(places.dir, 1, 1) = '/'"
    else
        REPLY="(places.dir = '${escaped}' or substr(places.dir, 1, length('${escaped}') + 1) = '${escaped}/')"
    fi
}

_histdb_date_expression() {
    local value="$1"
    local escaped="$(sql_escape "$value")"

    case "$value" in
        -*) REPLY="datetime('now', 'localtime', '${escaped}')" ;;
        today) REPLY="datetime('now', 'localtime', 'start of day')" ;;
        yesterday) REPLY="datetime('now', 'localtime', 'start of day', '-1 day')" ;;
        *) REPLY="datetime('${escaped}')" ;;
    esac
}

_histdb_write_query_output() {
    local query="$1"
    local separator="$2"
    local output_file exit_code

    output_file="$(mktemp)" || return 1
    _histdb_query -header -separator "$separator" "$query" >"$output_file"
    exit_code=$?

    if ((exit_code == 0)); then
        if [[ "$separator" == $'\x1f' ]]; then
            command iconv -f utf-8 -t utf-8 -c <"$output_file" | "${HISTDB_TABULATE_CMD[@]}"
            exit_code=$?
        else
            command cat -- "$output_file"
            exit_code=$?
        fi
    fi

    command rm -f -- "$output_file"
    return "$exit_code"
}

_histdb_select_query() {
    local where="$1"
    local order="$2"
    local limit="$3"
    local show_host="$4"
    local show_detail="$5"
    local home="$(sql_escape "$HOME")"
    local host_column=""
    local detail_columns=""
    local limit_clause=""

    ((show_host)) && host_column=', host'
    ((show_detail)) && detail_columns=', exit_status, duration'
    [[ -n "$limit" ]] && limit_clause="limit $limit"

    cat <<SQL
with filtered as (
    select
        history.id,
        history.session,
        history.exit_status,
        history.duration,
        history.start_time,
        commands.argv,
        places.host,
        places.dir,
        row_number() over (
            partition by history.command_id, history.place_id
            order by history.start_time desc, history.id desc
        ) as row_rank
    from history
    join commands on history.command_id = commands.id
    join places on history.place_id = places.id
    where ${where}
), selected as (
    select *
    from filtered
    where row_rank = 1
    order by start_time desc, id desc
    ${limit_clause}
)
select
    strftime(
        case
            when date(start_time, 'unixepoch', 'localtime') = date('now', 'localtime') then '%H:%M'
            else '%d/%m'
        end,
        start_time,
        'unixepoch',
        'localtime'
    ) as time,
    session as ses,
    case
        when dir = '${home}' then '~'
        when substr(dir, 1, length('${home}') + 1) = '${home}/'
            then '~' || substr(dir, length('${home}') + 1)
        else dir
    end as dir${host_column}${detail_columns},
    replace(replace(argv, char(10), ' ↩ '), char(9), ' ') as cmd
from selected
order by start_time ${order}, id ${order};
SQL
}

_histdb_count_matches() {
    local where="$1"

    _histdb_query "
select count(*)
from (
    select 1
    from history
    join commands on history.command_id = commands.id
    join places on history.place_id = places.id
    where ${where}
    group by history.command_id, history.place_id
);"
}

_histdb_delete_matches() {
    local where="$1"

    _histdb_query "
begin immediate;
delete from history
where id in (
    select history.id
    from history
    join commands on history.command_id = commands.id
    join places on history.place_id = places.id
    where ${where}
);
delete from commands
where id not in (select distinct command_id from history);
delete from places
where id not in (select distinct place_id from history);
commit;
"
}

histdb() {
    emulate -L zsh
    setopt local_options pipe_fail

    local -a hosts in_directories at_directories sessions terms conditions
    local separator=$'\x1f'
    local order='asc'
    local limit
    local show_host=0
    local show_detail=0
    local exact=0
    local debug=0
    local forget=0
    local assume_yes=0

    if [[ -p /dev/stdout ]]; then
        limit=""
    else
        limit=$((${LINES:-29} - 4))
        ((limit > 0)) || limit=25
    fi

    while (($#)); do
        case "$1" in
            --desc)
                order='desc'
                ;;
            --host)
                show_host=1
                if (($# > 1)) && [[ "$2" != -* ]]; then
                    hosts+=("$2")
                    shift
                fi
                ;;
            --host=*)
                show_host=1
                hosts+=("${1#--host=}")
                ;;
            --in | --at | -s)
                local option="$1"
                local value=""
                if (($# > 1)) && [[ "$2" != -* ]]; then
                    value="$2"
                    shift
                fi
                case "$option" in
                    --in) in_directories+=("${value:-$PWD}") ;;
                    --at) at_directories+=("${value:-$PWD}") ;;
                    -s) sessions+=("$value") ;;
                esac
                ;;
            --in=* | --at=* | -s=*)
                case "$1" in
                    --in=*) in_directories+=("${1#--in=}") ;;
                    --at=*) at_directories+=("${1#--at=}") ;;
                    -s=*) sessions+=("${1#-s=}") ;;
                esac
                ;;
            --detail) show_detail=1 ;;
            --exact) exact=1 ;;
            --forget) forget=1 ;;
            --yes) assume_yes=1 ;;
            --sep | --from | --until | --limit | --status)
                local option="$1"
                (($# > 1)) || {
                    print -u2 -- "histdb: ${option} requires a value"
                    return 1
                }
                local value="$2"
                shift
                case "$option" in
                    --sep) separator="$value" ;;
                    --from)
                        _histdb_date_expression "$value"
                        conditions+=("datetime(history.start_time, 'unixepoch', 'localtime') >= $REPLY")
                        ;;
                    --until)
                        _histdb_date_expression "$value"
                        conditions+=("datetime(history.start_time, 'unixepoch', 'localtime') <= $REPLY")
                        ;;
                    --limit)
                        [[ "$value" == <-> ]] || {
                            print -u2 -- "histdb: invalid limit: $value"
                            return 1
                        }
                        limit="$value"
                        ;;
                    --status)
                        if [[ "$value" == error ]]; then
                            conditions+=("history.exit_status <> 0")
                        elif [[ "$value" == <-> ]]; then
                            conditions+=("history.exit_status = $value")
                        else
                            print -u2 -- "histdb: invalid status: $value"
                            return 1
                        fi
                        ;;
                esac
                ;;
            --sep=* | --from=* | --until=* | --limit=* | --status=*)
                local option="${1%%=*}"
                local value="${1#*=}"
                set -- "$option" "$value" "${@:2}"
                continue
                ;;
            -d) debug=1 ;;
            -h | --help)
                _histdb_query_usage
                return 0
                ;;
            --)
                shift
                terms+=("$@")
                break
                ;;
            -*)
                print -u2 -- "histdb: unknown option: $1"
                return 1
                ;;
            *) terms+=("$1") ;;
        esac
        shift
    done

    _histdb_init || return 1

    if ((${#hosts})); then
        local -a host_conditions
        local host
        for host in "${hosts[@]}"; do
            host_conditions+=("places.host = '$(sql_escape "$host")'")
        done
        conditions+=("(${(j: or :)host_conditions})")
    elif ((!show_host)); then
        conditions+=("places.host = '$(sql_escape "$HISTDB_HOST")'")
    fi

    local directory
    for directory in "${in_directories[@]}"; do
        _histdb_tree_condition "$directory"
        conditions+=("$REPLY")
    done
    for directory in "${at_directories[@]}"; do
        conditions+=("places.dir = '$(sql_escape "$directory")'")
    done

    if ((${#sessions})); then
        local -a session_values
        local session
        for session in "${sessions[@]}"; do
            session="${session:-$HISTDB_SESSION}"
            [[ "$session" == <-> ]] || {
                print -u2 -- "histdb: invalid session: $session"
                return 1
            }
            session_values+=("$session")
        done
        conditions+=("history.session in (${(j:, :)session_values})")
    fi

    if ((${#terms})); then
        local search="${(j: :)terms}"
        if ((exact)); then
            conditions+=("commands.argv = '$(sql_escape "$search")'")
        else
            conditions+=("commands.argv glob '*$(sql_escape "$search")*'")
        fi
    fi

    local where="${(j: and :)conditions}"
    [[ -n "$where" ]] || where=1

    local query="$(_histdb_select_query "$where" "$order" "$limit" "$show_host" "$show_detail")" || return 1
    if ((debug)); then
        print -r -- "$query"
        return 0
    fi

    local count="$(_histdb_count_matches "$where")" || return 1
    _histdb_write_query_output "$query" "$separator" || return 1
    if [[ -n "$limit" ]] && ((limit < count)); then
        print -r -- "(showing $limit of $count results)"
    fi

    if ((forget)); then
        if ((assume_yes)); then
            REPLY=y
        else
            read -q 'REPLY?Forget all these results? [y/n] '
            print
        fi
        [[ "$REPLY" != [yY] ]] || _histdb_delete_matches "$where"
    fi
}
