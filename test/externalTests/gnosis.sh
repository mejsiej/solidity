#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# This file is part of solidity.
#
# solidity is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# solidity is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with solidity.  If not, see <http://www.gnu.org/licenses/>
#
# (c) 2019 solidity contributors.
#------------------------------------------------------------------------------

set -e

source scripts/common.sh
source test/externalTests/common.sh

verify_input "$@"
BINARY_TYPE="$1"
BINARY_PATH="$2"

function compile_fn { npx truffle compile; }
function test_fn { npm test; }

function gnosis_safe_test
{
    local repo="https://github.com/solidity-external-tests/safe-contracts.git"
    local branch=development_080
    local config_file="truffle-config.js"
    local settings_presets=(
        #ir-no-optimize            # "YulException: Variable var_call_430_mpos is 1 slot(s) too deep inside the stack."
        #ir-optimize-evm-only      # "YulException: Variable var_call_430_mpos is 1 slot(s) too deep inside the stack."
        ir-optimize-evm+yul
        #legacy-no-optimize        # "Stack too deep" error
        #legacy-optimize-evm-only  # "Stack too deep" error
        legacy-optimize-evm+yul
    )

    local selected_optimizer_presets
    selected_optimizer_presets=$(circleci_select_steps_multiarg "${settings_presets[@]}")
    print_optimizer_presets_or_exit "$selected_optimizer_presets"

    setup_solc "$DIR" "$BINARY_TYPE" "$BINARY_PATH"
    download_project "$repo" "$branch" "$DIR"
    [[ $BINARY_TYPE == native ]] && replace_global_solc "$BINARY_PATH"

    sed -i 's|github:gnosis/mock-contract#sol_0_5_0|github:solidity-external-tests/mock-contract#master_080|g' package.json

    neutralize_package_lock
    neutralize_package_json_hooks
    force_truffle_compiler_settings "$config_file" "$BINARY_TYPE" "${DIR}/solc" "$(first_word "$selected_optimizer_presets")"
    npm install --package-lock

    replace_version_pragmas
    [[ $BINARY_TYPE == solcjs ]] && force_solc_modules "${DIR}/solc"

    for preset in $selected_optimizer_presets; do
        truffle_run_test "$config_file" "$BINARY_TYPE" "${DIR}/solc" "$preset" compile_fn test_fn
    done
}

external_test Gnosis-Safe gnosis_safe_test
