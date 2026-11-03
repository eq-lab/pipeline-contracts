// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {BaseDeployer} from "../base/BaseDeployer.sol";

import {PipelineSecurityRegistry} from "../../src/PipelineSecurityRegistry.sol";

contract DeploySecurityRegistry is BaseDeployer {
    constructor(string memory tag) BaseDeployer(tag) {}

    function key() public pure override returns (string memory) {
        return "PipelineSecurityRegistry";
    }

    function _deployUpgradeable() internal override returns (address) {
        address authority = readPlain("AccessManager");
        (address loanRegistry,) = readUpgradeable("PipelineLoanRegistry");
        (address recordNft,) = readUpgradeable("PipelineSecurityRecordNft");

        Options memory opts;
        return Upgrades.deployUUPSProxy(
            "PipelineSecurityRegistry.sol",
            abi.encodeCall(PipelineSecurityRegistry.initialize, (authority, loanRegistry, recordNft)),
            opts
        );
    }

    function run(string memory tag) external returns (address proxy, address impl) {
        deploymentTag = tag;
        return deployUpgradeable();
    }
}
