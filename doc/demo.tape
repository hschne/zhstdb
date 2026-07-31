Output "demo.gif"
Output "demo.mp4"

Require sqlite3
Require fzf
Require zsh

Set Shell "zsh"
Set FontSize 20
Set FontFamily "DejaVu Sans Mono"
Set Width 1200
Set Height 720
Set Theme "TokyoNight"
Set Padding 24
Set Margin 0
Set BorderRadius 16
Set WindowBar "Rings"
Set WindowBarSize 36
Set Framerate 24
Set TypingSpeed 70ms
Set LoopOffset 15%

Hide
Type "rm -f /tmp/zhstdb-demo.db*" Enter
Type "sqlite3 /tmp/zhstdb-demo.db < doc/demo.sql" Enter
Type "export HOME=/home/demo HISTDB_FILE=/tmp/zhstdb-demo.db HISTDB_HOST=demo" Enter
Type "typeset -ga HISTDB_IGNORE_PATTERNS=('.*')" Enter
Type "source ./zhstdb.plugin.zsh" Enter
Type "bindkey -M emacs '^R' histdb-fzf-widget; bindkey -M viins '^R' histdb-fzf-widget; bindkey -M vicmd '^R' histdb-fzf-widget" Enter
Type "PROMPT='zhstdb % '" Enter
Type "clear" Enter
Show
Sleep 750ms
Ctrl+R
Sleep 500ms
Escape@0ms
Type@0ms "g"
Sleep 750ms
Type "git"
Sleep 1s
Down
Sleep 1s
Down
Sleep 1s
Up
Sleep 750ms
Enter
Sleep 2s
