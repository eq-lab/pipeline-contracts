// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {BaseDeployer} from "../base/BaseDeployer.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {WhitelistRegistry} from "../../src/WhitelistRegistry.sol";

contract DeployWhitelistRegistry is BaseDeployer {
    constructor(string memory tag) BaseDeployer(tag) {}

    function key() public pure override returns (string memory) {
        return "WhitelistRegistry";
    }

    function _deployUpgradeable() internal override returns (address) {
        address authority = readPlain("AccessManager");
        Options memory opts;
        return Upgrades.deployUUPSProxy(
            "WhitelistRegistry.sol", abi.encodeCall(WhitelistRegistry.initialize, authority), opts
        );
    }

    /// @notice Standalone entry point: `forge script script/deployers/DeployWhitelistRegistry.sol --sig "run(string)" <tag>`
    function run(string memory tag) external returns (address proxy, address impl) {
        deploymentTag = tag;
        return deployUpgradeable();
    }
}
