// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {BaseDeployer} from "../base/BaseDeployer.sol";

import {PipelineDealTokenFactory} from "../../src/PipelineDealTokenFactory.sol";

contract DeployDealTokenFactory is BaseDeployer {
    constructor(string memory tag) BaseDeployer(tag) {}

    function key() public pure override returns (string memory) {
        return "PipelineDealTokenFactory";
    }

    function _deployUpgradeable() internal override returns (address) {
        address authority = readPlain("AccessManager");
        (address loanRegistry,) = readUpgradeable("PipelineLoanRegistry");
        (address collateralRegistry,) = readUpgradeable("PipelineCollateralRegistry");

        Options memory opts;
        return Upgrades.deployUUPSProxy(
            "PipelineDealTokenFactory.sol",
            abi.encodeCall(PipelineDealTokenFactory.initialize, (authority, loanRegistry, collateralRegistry)),
            opts
        );
    }

    function run(string memory tag) external returns (address proxy, address impl) {
        deploymentTag = tag;
        return deployUpgradeable();
    }
}
