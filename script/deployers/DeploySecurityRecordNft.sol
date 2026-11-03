// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {BaseDeployer} from "../base/BaseDeployer.sol";

import {PipelineSecurityRecordNft} from "../../src/PipelineSecurityRecordNft.sol";

contract DeploySecurityRecordNft is BaseDeployer {
    constructor(string memory tag) BaseDeployer(tag) {}

    function key() public pure override returns (string memory) {
        return "PipelineSecurityRecordNft";
    }

    function _deployUpgradeable() internal override returns (address) {
        address authority = readPlain("AccessManager");

        Options memory opts;
        return Upgrades.deployUUPSProxy(
            "PipelineSecurityRecordNft.sol", abi.encodeCall(PipelineSecurityRecordNft.initialize, (authority)), opts
        );
    }

    function run(string memory tag) external returns (address proxy, address impl) {
        deploymentTag = tag;
        return deployUpgradeable();
    }
}
