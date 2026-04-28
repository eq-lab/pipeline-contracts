// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {BaseDeployer} from "../base/BaseDeployer.sol";

import {PipelineYieldMinterV1} from "../../src/PipelineYieldMinterV1.sol";

contract DeployYieldMinter is BaseDeployer {
    constructor(string memory tag) BaseDeployer(tag) {}

    function key() public pure override returns (string memory) {
        return "PipelineYieldMinterV1";
    }

    function _deployPlain() internal override returns (address) {
        address authority = readPlain("AccessManager");
        address yieldMintAuthority = address(uint160(uint256(valueOf("YieldMintAuthority", false))));
        (address stakedPlUsd,) = readUpgradeable("StakedPipelineUSD");

        PipelineYieldMinterV1 yieldMinter = new PipelineYieldMinterV1(authority, yieldMintAuthority, stakedPlUsd);
        return address(yieldMinter);
    }

    /// @notice Standalone entry point: `forge script DeployYieldMinter --sig "run(string)" <tag>`
    function run(string memory tag) external returns (address) {
        deploymentTag = tag;
        return deployPlain();
    }
}
