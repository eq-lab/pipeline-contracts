// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {WhitelistAccessedUpgradeable} from "../src/whitelist/WhitelistAccessedUpgradeable.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract PipelineUSDTest is PipelineTestSetUp {
    address public userOne = makeAddr("userOne");
    address public userTwo = makeAddr("userTwo");

    function setUp() public override {
        super.setUp();

        vm.prank(whitelistAdmin);
        whitelistRegistry.allow(userOne);

        vm.prank(whitelistAdmin);
        whitelistRegistry.allow(userTwo);

        vm.prank(whitelistAdmin);
        whitelistRegistry.allow(address(yieldMinter));

        deal(address(plUsd), userOne, 1_000_000_000);
    }

    function test_setUp() public view {
        assertEq(plUsd.authority(), address(authority));
        assertEq(plUsd.decimals(), 6);
    }

    function test_pause() public {
        vm.prank(userOne);
        plUsd.transfer(userTwo, 1_000);

        vm.prank(address(yieldMinter));
        plUsd.mint(address(withdrawalQueue), 1_000);

        vm.prank(address(withdrawalQueue));
        plUsd.burn(1_000);

        vm.prank(pauser);
        plUsd.pause();

        vm.prank(userOne);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        plUsd.transfer(userTwo, 1_000);

        vm.prank(address(yieldMinter));
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        plUsd.mint(address(withdrawalQueue), 1_000);

        vm.prank(address(withdrawalQueue));
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        plUsd.burn(1_000);

        vm.prank(pauser);
        plUsd.unpause();

        vm.prank(userOne);
        plUsd.transfer(userTwo, 1_000);

        vm.prank(address(yieldMinter));
        plUsd.mint(address(withdrawalQueue), 1_000);

        vm.prank(address(withdrawalQueue));
        plUsd.burn(1_000);
    }

    function testFuss_whitelistDisabled(address user) public {
        vm.assume(!whitelistRegistry.isAllowed(user));

        deal(address(plUsd), user, 1_000);

        vm.prank(whitelistAdmin);
        plUsd.disableWhitelist();
        assert(plUsd.isWhitelistDisabled());

        vm.prank(user);
        plUsd.transfer(whitelistAdmin, 1_000);

        vm.prank(whitelistAdmin);
        plUsd.enableWhitelist();
        assert(!plUsd.isWhitelistDisabled());

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(WhitelistAccessedUpgradeable.WhitelistAccessedNoAccess.selector, user));
        plUsd.transfer(whitelistAdmin, 1_000);
    }
}
