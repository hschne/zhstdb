typeset -g HISTDB_FZF_BACKEND="${0:A:h}/histdb-fzf-backend.zsh"

_histdb_fzf_backend() {
    command env \
        HISTDB_FILE="$HISTDB_FILE" \
        HISTDB_FZF_CWD="$PWD" \
        HISTDB_FZF_HOST="$HISTDB_HOST" \
        zsh "$HISTDB_FZF_BACKEND" "$@"
}

_histdb_fzf_command_line() {
    REPLY="env HISTDB_FILE=${(q)HISTDB_FILE} HISTDB_FZF_CWD=${(q)PWD} HISTDB_FZF_HOST=${(q)HISTDB_HOST} zsh ${(q)HISTDB_FZF_BACKEND}"
}

histdb-fzf-widget() {
    emulate -L zsh
    setopt local_options pipe_fail no_aliases

    local -a fzf_command lines
    local shortcuts='Alt-A at · Alt-I in · Alt-G global · Alt-J jump · Ctrl-R sort · Ctrl-/ preview'
    local header_at="scope: at · ${shortcuts}"
    local header_in="scope: in · ${shortcuts}"
    local header_global="scope: global · ${shortcuts}"
    local backend_command output key selected id command_text directory

    _histdb_init || return 1
    _histdb_fzf_command_line
    backend_command="$REPLY"

    if ((${+functions[__fzfcmd]})); then
        fzf_command=(${(z)"$(__fzfcmd)"})
    else
        fzf_command=(fzf)
    fi
    command -v "${fzf_command[1]}" >/dev/null 2>&1 || {
        zle -M 'histdb: fzf is not installed'
        return 1
    }

    output="$(
        _histdb_fzf_backend query in |
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
                --header="$header_in" \
                --preview="${backend_command} preview {1}" \
                --preview-window=up:6:wrap \
                --bind='ctrl-r:toggle-sort' \
                --bind='ctrl-/:toggle-preview' \
                --bind="alt-a:reload(${backend_command} query at)+change-header(${header_at})" \
                --bind="alt-i:reload(${backend_command} query in)+change-header(${header_in})" \
                --bind="alt-g:reload(${backend_command} query global)+change-header(${header_global})"
    )"
    (($? == 0)) || return 0

    lines=("${(@f)output}")
    ((${#lines} >= 2)) || return 0

    key="${lines[1]}"
    selected="${lines[2]}"
    id="${selected%%$'\x1f'*}"
    [[ "$id" == <-> ]] || return 0

    command_text="$(_histdb_fzf_backend command "$id")" || return 1
    [[ -n "$command_text" ]] || return 0

    if [[ "$key" == alt-j ]]; then
        directory="$(_histdb_fzf_backend directory "$id")" || return 1
        if [[ -d "$directory" ]]; then
            builtin cd -- "$directory"
        else
            zle -M "History directory no longer exists: ${directory}"
        fi
    fi

    BUFFER="$command_text"
    CURSOR=${#BUFFER}
    zle reset-prompt
}

if [[ -o interactive ]]; then
    zle -N histdb-fzf-widget
fi
