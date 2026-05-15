// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {WhitelistAccessUpgradeable} from "../src/whitelist/WhitelistAccessUpgradeable.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract WhitelistRegistryTest is PipelineTestSetUp {
    function testFuzz_allowSystemAddress(address systemAddress) public {
        vm.assume(!whitelistRegistry.isAllowed(systemAddress));

        vm.prank(whitelistAdmin);
        whitelistRegistry.allow(systemAddress);

        assert(whitelistRegistry.isAllowed(systemAddress));
    }

    function test_setUp() public view {
        assertEq(whitelistRegistry.authority(), address(authority));
    }

    function testFuzz_allowUser(address user) public {
        vm.assume(!whitelistRegistry.isAllowed(user));

        vm.prank(whitelistAdmin);
        whitelistRegistry.allow(user);

        assert(whitelistRegistry.isAllowed(user));
    }

    function testFuzz_disallow(address user) public {
        vm.assume(!whitelistRegistry.isAllowed(user));

        vm.prank(whitelistAdmin);
        whitelistRegistry.allow(user);

        vm.prank(whitelistAdmin);
        whitelistRegistry.disallow(user);

        assert(!whitelistRegistry.isAllowed(user));
    }

    function testFuzz_reverts(address user) public {
        vm.assume(!whitelistRegistry.isAllowed(user));

        vm.prank(whitelistAdmin);
        vm.expectRevert(abi.encodeWithSelector(WhitelistAccessUpgradeable.WhitelistAccessNoAllowance.selector));
        whitelistRegistry.disallow(user);

        vm.prank(whitelistAdmin);
        whitelistRegistry.allow(user);

        vm.prank(whitelistAdmin);
        vm.expectRevert(abi.encodeWithSelector(WhitelistAccessUpgradeable.WhitelistAccessAlreadyAllowed.selector));
        whitelistRegistry.allow(user);
    }
}
