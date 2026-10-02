// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {BaseDeployer} from "../base/BaseDeployer.sol";

import {PipelineMinter} from "../../src/PipelineMinter.sol";
import {RateLimiterUpgradeable} from "../../src/depositManager/RateLimiterUpgradeable.sol";

contract DeployMinter is BaseDeployer {
    constructor(string memory tag) BaseDeployer(tag) {}

    function key() public pure override returns (string memory) {
        return "PipelineMinter";
    }

    function _deployUpgradeable() internal override returns (address) {
        address authority = readPlain("AccessManager");
        (address stakedPipelineUSD,) = readUpgradeable("StakedPipelineUSD");
        (address loanRegistry,) = readUpgradeable("PipelineLoanRegistry");
        (address dealTokenFactory,) = readUpgradeable("PipelineDealTokenFactory");
        (address pocket,) = readUpgradeable("PipelinePocket");
        address treasury = address(uint160(uint256(valueOf("Treasury", false))));
        address usdc = address(uint160(uint256(valueOf("USDC", false))));

        RateLimiterUpgradeable.RateLimitConfig memory config = RateLimiterUpgradeable.RateLimitConfig({
            txLimit: uint256(valueOf("Minter__RateLimit__TxLimit", false)),
            windowLimit: uint256(valueOf("Minter__RateLimit__WindowLimit", false)),
            window: uint256(valueOf("Minter__RateLimit__Window", false)),
            shift: uint256(valueOf("Minter__RateLimit__Shift", true))
        });

        Options memory opts;
        return Upgrades.deployUUPSProxy(
            "PipelineMinter.sol",
            abi.encodeCall(
                PipelineMinter.initialize,
                (authority, stakedPipelineUSD, loanRegistry, treasury, dealTokenFactory, pocket, usdc, config)
            ),
            opts
        );
    }

    function run(string memory tag) external returns (address proxy, address impl) {
        deploymentTag = tag;
        return deployUpgradeable();
    }
}
