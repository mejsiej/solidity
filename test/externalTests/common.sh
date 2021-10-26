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

# Requires "${REPO_ROOT}/scripts/common.sh" to be included before.

CURRENT_EVM_VERSION=london

function verify_input
{
    if [ ! -f "$1" ]; then
        printError "Usage: $0 <path to soljson.js>"
        exit 1
    fi
}

function verify_version_input
{
    if [ -z "$1" ] || [ ! -f "$1" ] || [ -z "$2" ]; then
        printError "Usage: $0 <path to soljson.js> <version>"
        exit 1
    fi
}

function setup
{
    local soljson="$1"
    local branch="$2"

    setup_solcjs "$DIR" "$soljson" "$branch" "solc"
    cd solc
}

function setup_solcjs
{
    local dir="$1"
    local soljson="$2"
    local branch="${3:-master}"
    local path="${4:-solc/}"

    cd "$dir"
    printLog "Setting up solc-js..."
    git clone --depth 1 -b "$branch" https://github.com/ethereum/solc-js.git "$path"

    cd "$path"

    npm install
    cp "$soljson" soljson.js
    SOLCVERSION=$(./solcjs --version)
    SOLCVERSION_SHORT=$(echo "$SOLCVERSION" | sed -En 's/^([0-9.]+).*\+commit\.[0-9a-f]+.*$/\1/p')
    printLog "Using solcjs version $SOLCVERSION"
    cd ..
}

function download_project
{
    local repo="$1"
    local branch="$2"
    local dir="$3"

    printLog "Cloning $branch of $repo..."
    git clone --depth 1 "$repo" -b "$branch" "$dir/ext"
    cd ext
    echo "Current commit hash: $(git rev-parse HEAD)"
}

function force_truffle_version
{
    local version="$1"

    sed -i 's/"truffle":\s*".*"/"truffle": "'"$version"'"/g' package.json
}

function replace_version_pragmas
{
    # Replace fixed-version pragmas (part of Consensys best practice).
    # Include all directories to also cover node dependencies.
    printLog "Replacing fixed-version pragmas..."
    find . test -name '*.sol' -type f -print0 | xargs -0 sed -i -E -e 's/pragma solidity [^;]+;/pragma solidity >=0.0;/'
}

function neutralize_package_lock
{
    # Remove lock files (if they exist) to prevent them from overriding our changes in package.json
    printLog "Removing package lock files..."
    rm --force --verbose yarn.lock
    rm --force --verbose package-lock.json
}

function neutralize_package_json_hooks
{
    printLog "Disabling package.json hooks..."
    [[ -f package.json ]] || fail "package.json not found"
    sed -i 's|"prepublish": *".*"|"prepublish": ""|g' package.json
    sed -i 's|"prepare": *".*"|"prepare": ""|g' package.json
}

function force_solc_modules
{
    local custom_solcjs_path="${1:-solc/}"

    [[ -d node_modules/ ]] || assertFail

    printLog "Replacing all installed solc-js with a link to the latest version..."
    soljson_binaries=$(find node_modules -type f -path "*/solc/soljson.js")
    for soljson_binary in $soljson_binaries
    do
        local solc_module_path
        solc_module_path=$(dirname "$soljson_binary")

        printLog "Found and replaced solc-js in $solc_module_path"
        rm -r "$solc_module_path"
        ln -s "$custom_solcjs_path" "$solc_module_path"
    done
}

function force_truffle_compiler_settings
{
    local config_file="$1"
    local solc_path="$2"
    local level="$3"
    local evm_version="${4:-"$CURRENT_EVM_VERSION"}"

    printLog "Forcing Truffle compiler settings..."
    echo "-------------------------------------"
    echo "Config file: $config_file"
    echo "Compiler path: $solc_path"
    echo "Optimization level: $level"
    echo "Optimizer settings: $(optimizer_settings_for_level "$level")"
    echo "EVM version: $evm_version"
    echo "-------------------------------------"

    # Forcing the settings should always work by just overwriting the solc object. Forcing them by using a
    # dedicated settings objects should only be the fallback.
    echo "module.exports['compilers'] = $(truffle_compiler_settings "$solc_path" "$level" "$evm_version");" >> "$config_file"
}

function force_hardhat_compiler_binary
{
    local config_file="$1"
    local solc_path="$2"

    printLog "Configuring Hardhat..."
    echo "-------------------------------------"
    echo "Config file: ${config_file}"
    echo "Compiler path: ${solc_path}"

    local language="${config_file##*.}"
    hardhat_solc_build_subtask "$SOLCVERSION_SHORT" "$SOLCVERSION" "$solc_path" "$language" >> "$config_file"
}

function force_hardhat_compiler_settings
{
    local config_file="$1"
    local level="$2"
    local evm_version="${3:-"$CURRENT_EVM_VERSION"}"

    printLog "Configuring Hardhat..."
    echo "-------------------------------------"
    echo "Config file: ${config_file}"
    echo "Optimization level: ${level}"
    echo "Optimizer settings: $(optimizer_settings_for_level "$level")"
    echo "EVM version: ${evm_version}"
    echo "Compiler version: ${SOLCVERSION_SHORT}"
    echo "Compiler version (full): ${SOLCVERSION}"
    echo "-------------------------------------"

    local settings
    settings=$(hardhat_compiler_settings "$SOLCVERSION_SHORT" "$level" "$evm_version")
    if [[ $config_file == *\.js ]]; then
        echo "module.exports['solidity'] = ${settings}" >> "$config_file"
    else
        [[ $config_file == *\.ts ]] || assertFail
        echo "userConfig.solidity = {compilers: [${settings}]}"  >> "$config_file"
    fi
}

function truffle_verify_compiler_version
{
    local solc_version="$1"
    local full_solc_version="$2"

    printLog "Verify that the correct version (${solc_version}/${full_solc_version}) of the compiler was used to compile the contracts..."
    grep "$full_solc_version" --with-filename --recursive build/contracts || fail "Wrong compiler version detected."
}

function hardhat_verify_compiler_version
{
    local solc_version="$1"
    local full_solc_version="$2"

    printLog "Verify that the correct version (${solc_version}/${full_solc_version}) of the compiler was used to compile the contracts..."
    local build_info_files
    build_info_files=$(find . -path '*artifacts/build-info/*.json')
    for build_info_file in $build_info_files; do
        grep '"solcVersion": "'"${solc_version}"'"' --with-filename "$build_info_file" || fail "Wrong compiler version detected in ${build_info_file}."
        grep '"solcLongVersion": "'"${full_solc_version}"'"' --with-filename "$build_info_file" || fail "Wrong compiler version detected in ${build_info_file}."
    done
}

function truffle_clean
{
    rm -rf build/
}

function hardhat_clean
{
    rm -rf artifacts/ cache/
}

function run_test
{
    local compile_fn="$1"
    local test_fn="$2"

    replace_version_pragmas

    printLog "Running compile function..."
    $compile_fn

    printLog "Running test function..."
    $test_fn
}

function optimizer_settings_for_level
{
    local level="$1"

    case "$level" in
        1) echo "{enabled: false}" ;;
        2) echo "{enabled: true}" ;;
        3) echo "{enabled: true, details: {yul: true}}" ;;
        *)
            printError "Optimizer level not found. Please define OPTIMIZER_LEVEL=[1, 2, 3]"
            exit 1
            ;;
    esac
}

function truffle_compiler_settings
{
    local solc_path="$1"
    local level="$2"
    local evm_version="$3"

    echo "{"
    echo "    solc: {"
    echo "        version: \"${solc_path}\","
    echo "        settings: {"
    echo "            optimizer: $(optimizer_settings_for_level "$level"),"
    echo "            evmVersion: \"${evm_version}\""
    echo "        }"
    echo "    }"
    echo "}"
}

function hardhat_solc_build_subtask {
    local solc_version="$1"
    local full_solc_version="$2"
    local solc_path="$3"
    local language="$4"

    if [[ $language == js ]]; then
        echo "const {TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD} = require('hardhat/builtin-tasks/task-names');"
        echo "const assert = require('assert');"
        echo
        echo "subtask(TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD, async (args, hre, runSuper) => {"
    else
        [[ $language == ts ]] || assertFail
        echo "import {TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD} from 'hardhat/builtin-tasks/task-names';"
        echo "import assert = require('assert');"
        echo "import {subtask} from 'hardhat/config';"
        echo
        echo "subtask(TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD, async (args: any, _hre: any, _runSuper: any) => {"
    fi

    echo "    assert(args.solcVersion == '${solc_version}', 'Unexpected solc version: ' + args.solcVersion)"
    echo "    return {"
    echo "        compilerPath: '$(realpath "$solc_path")',"
    echo "        isSolcJs: true,"
    echo "        version: args.solcVersion,"
    echo "        longVersion: '${full_solc_version}'"
    echo "    }"
    echo "})"
}

function hardhat_compiler_settings {
    local solc_version="$1"
    local level="$2"
    local evm_version="$3"

    echo "{"
    echo "    version: '${solc_version}',"
    echo "    settings: {"
    echo "        optimizer: $(optimizer_settings_for_level "$level"),"
    echo "        evmVersion: '${evm_version}'"
    echo "    }"
    echo "}"
}

function compile_and_run_test
{
    local compile_fn="$1"
    local test_fn="$2"
    local verify_fn="$3"

    printLog "Running compile function..."
    $compile_fn
    $verify_fn "$SOLCVERSION_SHORT" "$SOLCVERSION"

    if [[ "$COMPILE_ONLY" == 1 ]]; then
        printLog "Skipping test function..."
    else
        printLog "Running test function..."
        $test_fn
    fi
}

function truffle_run_test
{
    local config_file="$1"
    local solc_path="$2"
    local optimizer_level="$3"
    local compile_fn="$4"
    local test_fn="$5"

    truffle_clean
    force_truffle_compiler_settings "$config_file" "$solc_path" "$optimizer_level"
    compile_and_run_test compile_fn test_fn truffle_verify_compiler_version
}

function hardhat_run_test
{
    local config_file="$1"
    local optimizer_level="$2"
    local compile_fn="$3"
    local test_fn="$4"

    hardhat_clean
    force_hardhat_compiler_settings "$config_file" "$optimizer_level"
    compile_and_run_test compile_fn test_fn hardhat_verify_compiler_version
}

function external_test
{
    local name="$1"
    local main_fn="$2"

    printTask "Testing $name..."
    echo "==========================="
    DIR=$(mktemp -d -t "ext-test-${name}-XXXXXX")
    (
        if [ -z "$main_fn" ]; then
            printError "Test main function not defined."
            exit 1
        fi
        $main_fn
    )
    rm -rf "$DIR"
    echo "Done."
}
