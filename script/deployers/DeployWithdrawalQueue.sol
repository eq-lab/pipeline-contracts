// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {BaseDeployer} from "../base/BaseDeployer.sol";

import {PipelineWithdrawalQueue} from "../../src/PipelineWithdrawalQueue.sol";

contract DeployWithdrawalQueue is BaseDeployer {
    constructor(string memory tag) BaseDeployer(tag) {}

    function key() public pure override returns (string memory) {
        return "PipelineWithdrawalQueue";
    }

    function _deployUpgradeable() internal override returns (address) {
        address authority = readPlain("AccessManager");
        (address pipelineUSD,) = readUpgradeable("PipelineUSD");

        address usdc = address(uint160(uint256(valueOf("USDC", false))));
        address withdrawalVerifier = address(uint160(uint256(valueOf("WithdrawalQueue__Verifier", false))));
        address tokenHolderMCP = address(uint160(uint256(valueOf("WithdrawalQueue__TokenHolderMCP", false))));

        Options memory opts;
        return Upgrades.deployUUPSProxy(
            "PipelineWithdrawalQueue.sol",
            abi.encodeCall(
                PipelineWithdrawalQueue.initialize, (authority, withdrawalVerifier, pipelineUSD, usdc, tokenHolderMCP)
            ),
            opts
        );
    }

    /// @notice Standalone entry point: `forge script script/deployers/DeployWithdrawalQueue.sol --sig "run(string)" <tag>`
    function run(string memory tag) external returns (address proxy, address impl) {
        deploymentTag = tag;
        return deployUpgradeable();
    }
}
