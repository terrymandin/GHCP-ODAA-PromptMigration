#!/usr/bin/env bash
set -euo pipefail

wallet_root='{{WALLET_ROOT}}'

printf '%s\n' 'TDE_STAGE=WALLET_DIRECTORY'
install -d -m 700 -- "$wallet_root"
install -d -m 700 -- "$wallet_root/tde"

test -d "$wallet_root/tde"
test "$(stat -c '%a' "$wallet_root/tde")" = '700'
printf '%s\n' 'TDE_WALLET_DIRECTORY=READY'
printf '%s\n' 'TDE_RESULT=WALLET_DIRECTORY_COMPLETE'
