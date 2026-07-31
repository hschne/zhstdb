#!/usr/bin/env zsh

emulate -LR zsh
setopt pipe_fail

local tests_directory="${0:A:h}"
local -a tests=("${tests_directory}"/test-*.zsh)
local passed=0
local failed=0
local test_file

for test_file in "${tests[@]}"; do
    printf '%-28s' "${test_file:t}"
    if zsh -f "$test_file"; then
        print 'ok'
        ((passed++))
    else
        print 'FAIL'
        ((failed++))
    fi
done

print
print -- "${passed} passed, ${failed} failed"
((failed == 0))
