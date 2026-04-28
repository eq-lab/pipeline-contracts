// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {BaseDeployer} from "../base/BaseDeployer.sol";

import {PipelineUSD} from "../../src/PipelineUSD.sol";

contract DeployPipelineUSD is BaseDeployer {
    constructor(string memory tag) BaseDeployer(tag) {}

    function key() public pure override returns (string memory) {
        return "PipelineUSD";
    }

    function _deployUpgradeable() internal override returns (address) {
        address authority = readPlain("AccessManager");
        (address whitelistRegistry,) = readUpgradeable("WhitelistRegistry");

        Options memory opts;
        return Upgrades.deployUUPSProxy(
            "PipelineUSD.sol", abi.encodeCall(PipelineUSD.initialize, (authority, whitelistRegistry)), opts
        );
    }

    /// @notice Standalone entry point: `forge script script/deployers/DeployPipelineUSD.sol --sig "run(string)" <tag>`
    function run(string memory tag) external returns (address proxy, address impl) {
        deploymentTag = tag;
        return deployUpgradeable();
    }
}
