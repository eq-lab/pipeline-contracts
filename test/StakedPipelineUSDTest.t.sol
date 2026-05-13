// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {WhitelistAccessedUpgradeable} from "../src/whitelist/WhitelistAccessedUpgradeable.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract StakedPipelineUSDTest is PipelineTestSetUp {
    address public user = makeAddr("user");

    function setUp() public override {
        super.setUp();

        vm.prank(whitelistAdmin);
        whitelistRegistry.allow(user);

        vm.prank(whitelistAdmin);
        whitelistRegistry.allow(address(sPlUsd));

        deal(address(plUsd), user, 1_000_000_000);
    }

    function test_setUp() public view {
        assertEq(sPlUsd.authority(), address(authority));
        assertEq(sPlUsd.asset(), address(plUsd));
    }

    function test_notWhitelistedWithdrawalRecipient(address recipient) public {
        vm.assume(!whitelistRegistry.isAllowed(recipient) && recipient != address(0));

        uint256 depositAmount = plUsd.balanceOf(user);

        vm.prank(user);
        plUsd.approve(address(sPlUsd), depositAmount);

        vm.prank(user);
        uint256 amount = sPlUsd.deposit(depositAmount, user);

        vm.prank(user);
        sPlUsd.transfer(recipient, amount);

        vm.prank(recipient);
        vm.expectRevert(
            abi.encodeWithSelector(WhitelistAccessedUpgradeable.WhitelistAccessedNoAccess.selector, recipient)
        );
        sPlUsd.redeem(amount, recipient, recipient);

        vm.prank(recipient);
        sPlUsd.transfer(user, amount);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(WhitelistAccessedUpgradeable.WhitelistAccessedNoAccess.selector, recipient)
        );
        sPlUsd.redeem(amount, recipient, user);
    }
}
