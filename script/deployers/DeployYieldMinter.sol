// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {BaseDeployer} from "../base/BaseDeployer.sol";

import {PipelineYieldMinter} from "../../src/PipelineYieldMinter.sol";

contract DeployYieldMinter is BaseDeployer {
    constructor(string memory tag) BaseDeployer(tag) {}

    function key() public pure override returns (string memory) {
        return "PipelineYieldMinter";
    }

    function _deployPlain() internal override returns (address) {
        address authority = readPlain("AccessManager");
        address treasury = address(uint160(uint256(valueOf("Treasury", false))));
        (address stakedPlUsd,) = readUpgradeable("StakedPipelineUSD");
        (address loanRegistry,) = readUpgradeable("PipelineLoanRegistry");

        PipelineYieldMinter yieldMinter = new PipelineYieldMinter(authority, stakedPlUsd, loanRegistry, treasury);
        return address(yieldMinter);
    }

    /// @notice Standalone entry point: `forge script DeployYieldMinter --sig "run(string)" <tag>`
    function run(string memory tag) external returns (address) {
        deploymentTag = tag;
        return deployPlain();
    }
}
