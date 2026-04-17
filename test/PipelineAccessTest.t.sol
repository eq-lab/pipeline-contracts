// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {IAccessManaged} from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {WhitelistAccessedUpgradeable} from "../src/whitelist/WhitelistAccessedUpgradeable.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract PipelineAccessTest is PipelineTestSetUp {
    function testFuzz_transfersWhitelist(address noAccess) public {
        vm.assume(noAccess != address(0));
        vm.assume(!whitelistRegistry.isAllowed(noAccess));

        address withAccess = makeAddr("withAccess");

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowUser(withAccess, type(uint256).max);

        vm.prank(noAccess);
        vm.expectRevert(
            abi.encodeWithSelector(WhitelistAccessedUpgradeable.WhitelistAccessedNoAccess.selector, noAccess)
        );
        plUsd.transfer(withAccess, 1);

        vm.prank(withAccess);
        vm.expectRevert(
            abi.encodeWithSelector(WhitelistAccessedUpgradeable.WhitelistAccessedNoAccess.selector, noAccess)
        );
        plUsd.transfer(noAccess, 1);
    }

    function testFuzz_trusteeAccess(address caller) public {
        vm.assume(caller != trustee);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        plUsd.mint(caller, 1);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        plUsd.burn(caller, 1);
    }

    function testFuzz_pauserAccess(address caller) public {
        vm.assume(caller != pauser);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        plUsd.pause();

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        plUsd.unpause();
    }

    function testFuzz_upgraderAccess(address caller) public {
        vm.assume(caller != upgrader);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        UUPSUpgradeable(address(plUsd)).upgradeToAndCall(address(plUsd), "");

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        UUPSUpgradeable(address(sPlUsd)).upgradeToAndCall(address(sPlUsd), "");

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        UUPSUpgradeable(address(whitelistRegistry)).upgradeToAndCall(address(whitelistRegistry), "");

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        UUPSUpgradeable(address(withdrawalQueue)).upgradeToAndCall(address(withdrawalQueue), "");
    }

    function testFuzz_queueManagerAccess(address caller) public {
        vm.assume(caller != queueManager);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        withdrawalQueue.increaseClaimable(1_000_000);
    }
}
