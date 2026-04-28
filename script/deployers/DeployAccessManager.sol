// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {BaseDeployer} from "../base/BaseDeployer.sol";

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

contract DeployAccessManager is BaseDeployer {
    constructor(string memory tag) BaseDeployer(tag) {}

    function key() public pure override returns (string memory) {
        return "AccessManager";
    }

    function _deployPlain() internal override returns (address) {
        address accessManagerAdmin = address(uint160(uint256(valueOf("AccessManagerOwner", false))));
        AccessManager accessManager = new AccessManager(accessManagerAdmin);
        return address(accessManager);
    }

    /// @notice Standalone entry point: `forge script script/deployers/DeployAccessManager.sol --sig "run(string)" <tag>`
    function run(string memory tag) external returns (address) {
        deploymentTag = tag;
        return deployPlain();
    }
}
