// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {Script, console} from "forge-std/Script.sol";

import {ChainValues} from "./ChainValues.sol";

/// @notice Read/write/skip helpers for deployments/{chain}-{deploymentTag}.json.
contract Deployments is ChainValues, Script {
    string public deploymentTag;

    function deploymentPath() internal view returns (string memory) {
        return string.concat("deployments/", nameOf(block.chainid), "-", deploymentTag, ".json");
    }

    function readUpgradeable(string memory key) internal view returns (address proxy, address implementation) {
        string memory path = deploymentPath();
        if (!vm.exists(path)) return (address(0), address(0));

        string memory json = vm.readFile(path);
        string memory base = string.concat("$[\"", key, "\"]");
        if (!vm.keyExistsJson(json, base)) return (address(0), address(0));

        proxy = vm.parseJsonAddress(json, string.concat(base, ".proxy"));
        implementation = vm.parseJsonAddress(json, string.concat(base, ".implementation"));
    }

    function readPlain(string memory key) internal view returns (address addr) {
        string memory path = deploymentPath();
        if (!vm.exists(path)) return address(0);

        string memory json = vm.readFile(path);
        string memory base = string.concat("$[\"", key, "\"]");
        if (!vm.keyExistsJson(json, base)) return address(0);

        addr = vm.parseJsonAddress(json, string.concat(base, ".address"));
    }

    function writeUpgradeable(string memory key, address proxy, address implementation) internal {
        // Build the entry as pretty-printed lines with 4-space indent
        // (2 for object level, 2 more for nested fields).
        string memory entry = string.concat(
            "{\n",
            "    \"proxy\": \"",
            vm.toString(proxy),
            "\",\n",
            "    \"implementation\": \"",
            vm.toString(implementation),
            "\"\n",
            "  }"
        );
        _upsertEntry(deploymentPath(), key, entry);
    }

    function writePlain(string memory key, address addr) internal {
        string memory entry = string.concat("{\n", "    \"address\": \"", vm.toString(addr), "\"\n", "  }");
        _upsertEntry(deploymentPath(), key, entry);
    }

    function _upsertEntry(string memory path, string memory key, string memory entry) private {
        // Ensure deployments/ exists.
        string[] memory mkdir = new string[](3);
        mkdir[0] = "mkdir";
        mkdir[1] = "-p";
        mkdir[2] = "deployments";
        vm.ffi(mkdir);

        // Collect existing keys (in original order) and their pre-formatted entries.
        string[] memory keys;
        string[] memory entries;
        (keys, entries) = _readExisting(path);

        // Find existing index of this key, if any.
        int256 idx = -1;
        for (uint256 i = 0; i < keys.length; i++) {
            if (keccak256(bytes(keys[i])) == keccak256(bytes(key))) {
                idx = int256(i);
                break;
            }
        }

        // Emit new file.
        string memory out = "{";
        bool first = true;

        if (idx == -1) {
            // Append: replay all existing keys, then the new one.
            for (uint256 i = 0; i < keys.length; i++) {
                out = _appendKv(out, keys[i], entries[i], first);
                first = false;
            }
            out = _appendKv(out, key, entry, first);
        } else {
            // Update in place: replay all keys, swapping the entry at idx.
            for (uint256 i = 0; i < keys.length; i++) {
                string memory v = (int256(i) == idx) ? entry : entries[i];
                out = _appendKv(out, keys[i], v, first);
                first = false;
            }
        }

        out = string.concat(out, "\n}\n");
        vm.writeFile(path, out);
    }

    function _appendKv(string memory acc, string memory k, string memory v, bool first)
        private
        pure
        returns (string memory)
    {
        return string.concat(acc, first ? "\n" : ",\n", "  \"", k, "\": ", v);
    }

    /// @dev Parse the existing file into (keys[], entries[]) where each
    ///      entry is the JSON object (already pretty-formatted with this
    ///      library's 4-space inner indent / closing-brace-at-col-2 shape).
    ///      Returns empty arrays if the file is missing or empty.
    function _readExisting(string memory path) private view returns (string[] memory keys, string[] memory entries) {
        if (!vm.exists(path)) {
            return (new string[](0), new string[](0));
        }

        string memory json = vm.readFile(path);
        if (bytes(json).length == 0) {
            return (new string[](0), new string[](0));
        }

        keys = vm.parseJsonKeys(json, "$");
        entries = new string[](keys.length);

        // For each key, re-emit its value as pretty-formatted JSON.
        // We support our own two record shapes here.
        for (uint256 i = 0; i < keys.length; i++) {
            string memory base = string.concat("$[\"", keys[i], "\"]");

            if (vm.keyExistsJson(json, string.concat(base, ".proxy"))) {
                address p = vm.parseJsonAddress(json, string.concat(base, ".proxy"));
                address impl = vm.parseJsonAddress(json, string.concat(base, ".implementation"));
                entries[i] = string.concat(
                    "{\n",
                    "    \"proxy\": \"",
                    vm.toString(p),
                    "\",\n",
                    "    \"implementation\": \"",
                    vm.toString(impl),
                    "\"\n",
                    "  }"
                );
            } else if (vm.keyExistsJson(json, string.concat(base, ".address"))) {
                address a = vm.parseJsonAddress(json, string.concat(base, ".address"));
                entries[i] = string.concat("{\n", "    \"address\": \"", vm.toString(a), "\"\n", "  }");
            } else {
                revert(string.concat("Deployments: unknown entry shape for key ", keys[i]));
            }
        }
    }
}
