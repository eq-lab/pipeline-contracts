// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {BaseDeployer} from "../base/BaseDeployer.sol";

import {PipelineLoanRegistryReader} from "../../src/PipelineLoanRegistryReader.sol";

contract DeployLoanRegistryReader is BaseDeployer {
    constructor(string memory tag) BaseDeployer(tag) {}

    function key() public pure override returns (string memory) {
        return "PipelineLoanRegistryReader";
    }

    function _deployPlain() internal override returns (address) {
        (address loanRegistry,) = readUpgradeable("PipelineLoanRegistry");
        return address(new PipelineLoanRegistryReader(loanRegistry));
    }

    function run(string memory tag) external returns (address) {
        deploymentTag = tag;
        return deployPlain();
    }
}
