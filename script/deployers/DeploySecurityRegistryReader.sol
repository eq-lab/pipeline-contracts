// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {BaseDeployer} from "../base/BaseDeployer.sol";

import {PipelineSecurityRegistryReader} from "../../src/PipelineSecurityRegistryReader.sol";

contract DeploySecurityRegistryReader is BaseDeployer {
    constructor(string memory tag) BaseDeployer(tag) {}

    function key() public pure override returns (string memory) {
        return "PipelineSecurityRegistryReader";
    }

    function _deployPlain() internal override returns (address) {
        (address securityRegistry,) = readUpgradeable("PipelineSecurityRegistry");
        return address(new PipelineSecurityRegistryReader(securityRegistry));
    }

    function run(string memory tag) external returns (address) {
        deploymentTag = tag;
        return deployPlain();
    }
}
