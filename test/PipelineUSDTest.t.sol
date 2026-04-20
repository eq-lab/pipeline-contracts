// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract PipelineUSDTest is PipelineTestSetUp {
    address public userOne = makeAddr("userOne");
    address public userTwo = makeAddr("userTwo");

    function setUp() public override {
        super.setUp();

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowSystemAddress(userOne);

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowSystemAddress(userTwo);

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowSystemAddress(address(0));

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowSystemAddress(trustee);

        deal(address(plUsd), userOne, 1_000_000_000);
    }

    function test_setUp() public view {
        assertEq(plUsd.authority(), address(authority));
        assertEq(plUsd.decimals(), 6);
    }

    function test_pause() public {
        vm.prank(userOne);
        plUsd.transfer(userTwo, 1_000);

        vm.prank(trustee);
        plUsd.mint(address(withdrawalQueue), 1_000);

        vm.prank(address(withdrawalQueue));
        plUsd.burn(1_000);

        vm.prank(pauser);
        plUsd.pause();

        vm.prank(userOne);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        plUsd.transfer(userTwo, 1_000);

        vm.prank(trustee);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        plUsd.mint(trustee, 1_000);

        vm.prank(address(withdrawalQueue));
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        plUsd.burn(1_000);

        vm.prank(pauser);
        plUsd.unpause();

        vm.prank(userOne);
        plUsd.transfer(userTwo, 1_000);

        vm.prank(trustee);
        plUsd.mint(address(withdrawalQueue), 1_000);

        vm.prank(address(withdrawalQueue));
        plUsd.burn(1_000);
    }
}
