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

function compile_fn { npm run compile; }
function test_fn { npm test; }

function zeppelin_test
{
    local repo="https://github.com/OpenZeppelin/openzeppelin-contracts.git"
    local branch=master
    local config_file="hardhat.config.js"
    local settings_presets=(
        #ir-no-optimize           # "YulException: Variable var_account_852 is 4 slot(s) too deep inside the stack."
        #ir-optimize-evm-only     # "YulException: Variable var_account_852 is 4 slot(s) too deep inside the stack."
        #ir-optimize-evm+yul      # Compiles but tests fail. See https://github.com/nomiclabs/hardhat/issues/2115
        legacy-no-optimize
        legacy-optimize-evm-only
        legacy-optimize-evm+yul
    )

    local selected_optimizer_presets
    selected_optimizer_presets=$(circleci_select_steps_multiarg "${settings_presets[@]}")
    print_optimizer_presets_or_exit "$selected_optimizer_presets"

    setup_solc "$DIR" "$BINARY_TYPE" "$BINARY_PATH"
    download_project "$repo" "$branch" "$DIR"

    neutralize_package_json_hooks
    force_hardhat_compiler_binary "$config_file" "$BINARY_TYPE" "$BINARY_PATH"
    force_hardhat_compiler_settings "$config_file" "$(first_word "$selected_optimizer_presets")"
    npm install

    replace_version_pragmas

    for preset in $selected_optimizer_presets; do
        hardhat_run_test "$config_file" "$preset" compile_fn test_fn
    done
}

external_test Zeppelin zeppelin_test
