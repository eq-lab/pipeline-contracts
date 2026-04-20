// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {WhitelistAccessUpgradeable} from "../src/whitelist/WhitelistAccessUpgradeable.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract WhitelistRegistryTest is PipelineTestSetUp {
    function testFuzz_allowSystemAddress(address systemAddress) public {
        vm.assume(!whitelistRegistry.isAllowed(systemAddress));

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowSystemAddress(systemAddress);

        assert(whitelistRegistry.isAllowed(systemAddress));
        assertEq(whitelistRegistry.allowedUntil(systemAddress), type(uint256).max);
    }

    function test_setUp() public view {
        assertEq(whitelistRegistry.authority(), address(authority));
    }

    function testFuzz_allowUser(address user, uint256 until) public {
        vm.assume(user != address(0) && !whitelistRegistry.isAllowed(user));
        vm.assume(until != type(uint256).max && until > block.timestamp);

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowUser(user, until);

        assert(whitelistRegistry.isAllowed(user));
        assertEq(whitelistRegistry.allowedUntil(user), until);

        vm.warp(until + 1);
        assert(!whitelistRegistry.isAllowed(user));
    }

    function testFuzz_disallow(address user) public {
        vm.assume(user != address(0) && !whitelistRegistry.isAllowed(user));

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowSystemAddress(user);

        vm.prank(whitelistAdmin);
        whitelistRegistry.disallow(user);

        assert(!whitelistRegistry.isAllowed(user));
        assertEq(whitelistRegistry.allowedUntil(user), 0);

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowUser(user, block.timestamp + 1000);

        vm.prank(whitelistAdmin);
        whitelistRegistry.disallow(user);

        assert(!whitelistRegistry.isAllowed(user));
        assertEq(whitelistRegistry.allowedUntil(user), 0);
    }

    function testFuzz_prolongateAllowance(address user, uint256 until) public {
        vm.assume(user != address(0) && !whitelistRegistry.isAllowed(user));
        vm.assume(until != type(uint256).max && until > block.timestamp);

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowUser(user, until);

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowUser(user, until + 1);

        assert(whitelistRegistry.isAllowed(user));
        assertEq(whitelistRegistry.allowedUntil(user), until + 1);
    }

    function testFuzz_reverts(address user) public {
        vm.assume(user != address(0) && !whitelistRegistry.isAllowed(user));

        vm.prank(whitelistAdmin);
        vm.expectRevert(abi.encodeWithSelector(WhitelistAccessUpgradeable.WhitelistAccessZeroAddress.selector));
        whitelistRegistry.allowUser(address(0), 0);

        vm.prank(whitelistAdmin);
        vm.expectRevert(abi.encodeWithSelector(WhitelistAccessUpgradeable.WhitelistAccessNoAllowance.selector));
        whitelistRegistry.disallow(user);

        vm.prank(whitelistAdmin);
        vm.expectRevert(abi.encodeWithSelector(WhitelistAccessUpgradeable.WhitelistAccessAllowanceInPast.selector));
        whitelistRegistry.allowUser(user, block.timestamp - 1);

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowUser(user, block.timestamp + 1);

        vm.prank(whitelistAdmin);
        vm.expectRevert(abi.encodeWithSelector(WhitelistAccessUpgradeable.WhitelistAccessAlreadyAllowed.selector));
        whitelistRegistry.allowUser(user, block.timestamp + 1);
    }
}
