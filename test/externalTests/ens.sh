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

verify_input "$1"
export SOLJSON="$1"

function compile_fn { yarn build; }
function test_fn { yarn test; }

function ens_test
{
    local repo="https://github.com/ensdomains/ens-contracts.git"
    local branch=master
    local config_file="hardhat.config.js"
    local min_optimizer_level=1
    local max_optimizer_level=3

    setup_solcjs "$DIR" "$SOLJSON"
    download_project "$repo" "$branch" "$DIR"

    neutralize_package_lock
    neutralize_package_json_hooks
    force_hardhat_compiler_binary "$config_file" "$SOLJSON"
    force_hardhat_compiler_settings "$config_file" "$min_optimizer_level"
    yarn install

    replace_version_pragmas
    neutralize_packaged_contracts

    for level in $(seq "$min_optimizer_level" "$max_optimizer_level"); do
        hardhat_run_test "$config_file" "$level" compile_fn test_fn
    done
}

external_test ENS ens_test
