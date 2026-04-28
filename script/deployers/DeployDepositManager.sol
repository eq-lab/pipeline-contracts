// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {BaseDeployer} from "../base/BaseDeployer.sol";

import {PipelineDepositManager} from "../../src/PipelineDepositManager.sol";
import {RateLimiterUpgradeable} from "../../src/depositManager/RateLimiterUpgradeable.sol";

contract DeployDepositManager is BaseDeployer {
    constructor(string memory tag) BaseDeployer(tag) {}

    function key() public pure override returns (string memory) {
        return "PipelineDepositManager";
    }

    function _deployUpgradeable() internal override returns (address) {
        address authority = readPlain("AccessManager");
        address custodian = address(uint160(uint256(valueOf("Custodian", false))));
        address usdc = address(uint160(uint256(valueOf("USDC", false))));
        (address pipelineUSD,) = readUpgradeable("PipelineUSD");

        uint256 minDeposit = uint256(valueOf("DepositManager__MinDeposit", false));

        RateLimiterUpgradeable.RateLimitConfig memory config = RateLimiterUpgradeable.RateLimitConfig({
            txLimit: uint256(valueOf("DepositManager__RateLimit__TxLimit", false)),
            windowLimit: uint256(valueOf("DepositManager__RateLimit__WindowLimit", false)),
            window: uint256(valueOf("DepositManager__RateLimit__Window", false)),
            shift: uint256(valueOf("DepositManager__RateLimit__Shift", true))
        });

        Options memory opts;
        return Upgrades.deployUUPSProxy(
            "PipelineDepositManager.sol",
            abi.encodeCall(
                PipelineDepositManager.initialize, (authority, custodian, usdc, pipelineUSD, minDeposit, config)
            ),
            opts
        );
    }

    /// @notice Standalone entry point: `forge script script/deployers/DeployDepositManager.sol --sig "run(string)" <tag>`
    function run(string memory tag) external returns (address proxy, address impl) {
        deploymentTag = tag;
        return deployUpgradeable();
    }
}
