// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {Deployments} from "./Deployments.sol";

/// @notice Base contract for per-contract deployer scripts.
///
/// Subclasses implement `key()` plus one of:
///   - `_deployUpgradeable()` — for ERC1967Proxy + impl
///   - `_deployPlain()`       — for non-upgradeable contracts
abstract contract BaseDeployer is Script, Deployments {
    constructor(string memory tag) {
        deploymentTag = tag;
    }

    /// @notice Stable identifier for this contract in the deployments file.
    function key() public view virtual returns (string memory);

    /// @notice Deploy (or load) an upgradeable contract.
    function deployUpgradeable() public returns (address proxy, address implementation) {
        string memory k = key();

        (proxy, implementation) = readUpgradeable(k);
        if (proxy != address(0)) {
            console.log(string.concat("[skip] ", k));
            console.log("  proxy          :", proxy);
            console.log("  implementation :", implementation);
            return (proxy, implementation);
        }

        vm.startBroadcast();
        proxy = _deployUpgradeable();
        vm.stopBroadcast();

        implementation = Upgrades.getImplementationAddress(proxy);

        Deployments.writeUpgradeable(k, proxy, implementation);

        console.log(string.concat("[new]  ", k));
        console.log("  proxy          :", proxy);
        console.log("  implementation :", implementation);
    }

    /// @notice Deploy (or load) a non-upgradeable contract.
    function deployPlain() public returns (address addr) {
        string memory k = key();

        addr = readPlain(k);
        if (addr != address(0)) {
            console.log(string.concat("[skip] ", k));
            console.log("  address :", addr);
            return addr;
        }

        vm.startBroadcast();
        addr = _deployPlain();
        vm.stopBroadcast();

        Deployments.writePlain(k, addr);

        console.log(string.concat("[new]  ", k));
        console.log("  address :", addr);
    }

    /// @dev Override in upgradeable deployers. Should call
    ///      `Upgrades.deployUUPSProxy` (or `deployTransparentProxy`) and
    ///      return the proxy address.
    function _deployUpgradeable() internal virtual returns (address) {}

    /// @dev Override in non-upgradeable deployers. Should `new` the contract
    ///      and return its address.
    function _deployPlain() internal virtual returns (address) {}
}
