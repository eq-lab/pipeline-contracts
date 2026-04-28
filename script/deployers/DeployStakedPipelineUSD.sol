// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {BaseDeployer} from "../base/BaseDeployer.sol";

import {PipelineUSD} from "../../src/PipelineUSD.sol";

contract DeployStakedPipelineUSD is BaseDeployer {
    constructor(string memory tag) BaseDeployer(tag) {}

    function key() public pure override returns (string memory) {
        return "StakedPipelineUSD";
    }

    function _deployUpgradeable() internal override returns (address) {
        (address pipelineUSD,) = readUpgradeable("PipelineUSD");
        address authority = readPlain("AccessManager");

        Options memory opts;
        return Upgrades.deployUUPSProxy(
            "StakedPipelineUSD.sol", abi.encodeCall(PipelineUSD.initialize, (pipelineUSD, authority)), opts
        );
    }

    /// @notice Standalone entry point: `forge script script/deployers/DeployStakedPipelineUSD.sol --sig "run(string)" <tag>`
    function run(string memory tag) external returns (address proxy, address impl) {
        deploymentTag = tag;
        return deployUpgradeable();
    }
}
