// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {IAccessManaged} from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {WhitelistAccessedUpgradeable} from "../src/whitelist/WhitelistAccessedUpgradeable.sol";
import {ILoanRegistry} from "../src/interfaces/ILoanRegistry.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract PipelineAccessTest is PipelineTestSetUp {
    function testFuzz_transfersWhitelist(address noAccess) public {
        vm.assume(noAccess != address(0));
        vm.assume(!whitelistRegistry.isAllowed(noAccess));

        address withAccess = makeAddr("withAccess");

        vm.prank(whitelistAdmin);
        whitelistRegistry.allow(withAccess);

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
        UUPSUpgradeable(address(depositManager)).upgradeToAndCall(address(depositManager), "");

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        UUPSUpgradeable(address(withdrawalQueue)).upgradeToAndCall(address(withdrawalQueue), "");

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        UUPSUpgradeable(address(loanRegistry)).upgradeToAndCall(address(loanRegistry), "");
    }

    function testFuzz_yieldMintAccess(address caller) public {
        vm.assume(caller != yieldMinterManager);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        yieldMinter.mintYield(1, "");
    }

    function testFuzz_depositManagerAccess(address caller) public {
        vm.assume(caller != depositManagerAdmin);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        depositManager.setMinDeposit(1);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        depositManager.setCustodian(caller);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        depositManager.increaseTxLimit(1);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        depositManager.decreaseTxLimit(1);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        depositManager.increaseWindowLimit(1);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        depositManager.decreaseWindowLimit(1);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        depositManager.setVerifier(caller);
    }

    function testFuzz_queueManagerAccess(address caller) public {
        vm.assume(caller != queueManager);

        address newIntoTokenHolder = makeAddr("newIntoTokenHolder");

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        withdrawalQueue.changeIntoTokenHolder(newIntoTokenHolder);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        withdrawalQueue.setShutdownRate(1);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        withdrawalQueue.setVerifier(caller);
    }

    function testFuzz_loanRegistryAccess(address caller) public {
        vm.assume(caller != loanRegistryManager);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.mintLoan(caller, "", 0, bytes32(0));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.updateStatus(0, ILoanRegistry.LoanStatus.WatchList);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.updateCCR(0, 0);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.updateLocation(0, bytes32(0));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.setDefault(0);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.closeLoan(0, ILoanRegistry.ClosureReason.None);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.recordPayment(0, 0, 0, 0, 0);
    }
}
