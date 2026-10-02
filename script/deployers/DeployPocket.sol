// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {BaseDeployer} from "../base/BaseDeployer.sol";

import {PipelinePocket} from "../../src/PipelinePocket.sol";

contract DeployPocket is BaseDeployer {
    constructor(string memory tag) BaseDeployer(tag) {}

    function key() public pure override returns (string memory) {
        return "PipelinePocket";
    }

    function _deployUpgradeable() internal override returns (address) {
        address authority = readPlain("AccessManager");
        (address stakedPipelineUSD,) = readUpgradeable("StakedPipelineUSD");

        Options memory opts;
        return Upgrades.deployUUPSProxy(
            "PipelinePocket.sol", abi.encodeCall(PipelinePocket.initialize, (authority, stakedPipelineUSD)), opts
        );
    }

    function run(string memory tag) external returns (address proxy, address impl) {
        deploymentTag = tag;
        return deployUpgradeable();
    }
}
