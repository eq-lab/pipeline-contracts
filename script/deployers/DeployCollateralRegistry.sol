// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {BaseDeployer} from "../base/BaseDeployer.sol";

import {PipelineCollateralRegistry} from "../../src/PipelineCollateralRegistry.sol";

contract DeployCollateralRegistry is BaseDeployer {
    constructor(string memory tag) BaseDeployer(tag) {}

    function key() public pure override returns (string memory) {
        return "PipelineCollateralRegistry";
    }

    function _deployUpgradeable() internal override returns (address) {
        address authority = readPlain("AccessManager");
        (address loanRegistry,) = readUpgradeable("PipelineLoanRegistry");

        Options memory opts;
        return Upgrades.deployUUPSProxy(
            "PipelineCollateralRegistry.sol",
            abi.encodeCall(PipelineCollateralRegistry.initialize, (authority, loanRegistry)),
            opts
        );
    }

    function run(string memory tag) external returns (address proxy, address impl) {
        deploymentTag = tag;
        return deployUpgradeable();
    }
}
