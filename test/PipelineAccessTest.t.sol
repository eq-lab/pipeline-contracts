// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {IAccessManaged} from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {WhitelistAccessedUpgradeable} from "../src/whitelist/WhitelistAccessedUpgradeable.sol";
import {ILoanRegistry} from "../src/interfaces/ILoanRegistry.sol";
import {MinterUpgradeable} from "../src/minter/MinterUpgradeable.sol";
import {CollateralRegistryUpgradeable} from "../src/collateralRegistry/CollateralRegistryUpgradeable.sol";

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

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        sPlUsd.pause();

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        sPlUsd.unpause();
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

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        depositManager.pause();

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        depositManager.unpause();
    }

    function testFuzz_queueManagerAccess(address caller) public {
        vm.assume(caller != queueManager);

        address newAssetHolder = makeAddr("newAssetHolder");

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        withdrawalQueue.setAssetHolder(newAssetHolder);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        withdrawalQueue.setShutdownRate(1);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        withdrawalQueue.setVerifier(caller);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        withdrawalQueue.pause();

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        withdrawalQueue.unpause();
    }

    function testFuzz_loanRegistryAccess(address caller) public {
        vm.assume(caller != loanRegistryManager);

        ILoanRegistry.ImmutableLoanData memory loanData;

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.drawLoan("", loanData);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.updateMutable(0, ILoanRegistry.LoanStatus.Performing, "");

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.rollover(0, 0, 0);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.amendEconomics(0, 0, 0);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.setDefault(0);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.writeDown(0, 0);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.adjustInterest(0, 0, bytes32(0));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.cure(0);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.closeLoan(0, ILoanRegistry.ClosureReason.None);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.closeDefaulted(0, ILoanRegistry.ClosureReason.None);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.pause();

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.unpause();
    }

    function testFuzz_loanRegistryMinterAccess(address caller) public {
        vm.assume(caller != address(minter));

        ILoanRegistry.RepaymentData memory repayment;

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.disburse(0, 0);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.undisburse(0, 0, 0);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.recordPayment(0, repayment);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.unrecordPayment(0, 0);
    }

    function testFuzz_loanRegistryAdminAccess(address caller) public {
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.setCapitalWallet(caller);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.setStakedPlUsd(caller);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.setPocket(caller);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.setMaxFeeBps(1);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        loanRegistry.setMaxResidual(1);
    }

    function testFuzz_stakedPlUsdCarveOutAccess(address caller) public {
        vm.assume(caller != address(loanRegistry));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        sPlUsd.carveOut(0, 0);
    }

    function testFuzz_stakedPlUsdMinterAccess(address caller) public {
        vm.assume(caller != address(minter));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        sPlUsd.pull(0);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        sPlUsd.burnShares(caller, 0);
    }

    function testFuzz_stakedPlUsdAdminAccess(address caller) public {
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        sPlUsd.setPocket(caller);
    }

    function testFuzz_pocketAccess(address caller) public {
        vm.assume(caller != address(sPlUsd));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        pocket.open(0, 0, 0, 0);
    }

    function testFuzz_pocketMinterAccess(address caller) public {
        vm.assume(caller != address(minter));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        pocket.release(0, 0, 0);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        pocket.unrelease(0, 0, 0);
    }

    function testFuzz_pocketLoanRegistryAccess(address caller) public {
        vm.assume(caller != address(loanRegistry));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        pocket.burn(0, 0);
    }

    function testFuzz_pocketPauserAccess(address caller) public {
        vm.assume(caller != pauser);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        pocket.pause();

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        pocket.unpause();
    }

    function testFuzz_minterMintCallerAccess(address caller) public {
        vm.assume(caller != mintCaller);

        ILoanRegistry.RepaymentData memory repayment;
        bytes memory unauthorized = abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller);

        vm.startPrank(caller);
        vm.expectRevert(unauthorized);
        minter.recordWireIn(caller, 0, 0, bytes32(0), bytes32(0));
        vm.expectRevert(unauthorized);
        minter.repay(0, repayment, 0, bytes32(0), 0);
        vm.expectRevert(unauthorized);
        minter.recordIncome(0, 0, bytes32(0));
        vm.stopPrank();
    }

    function testFuzz_minterOpsAccess(address caller) public {
        vm.assume(caller != minterOps);

        bytes memory unauthorized = abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller);

        vm.startPrank(caller);
        vm.expectRevert(unauthorized);
        minter.assignWireIn(0, caller, bytes32(0));
        vm.expectRevert(unauthorized);
        minter.returnWireIn(0, bytes32(0));
        vm.expectRevert(unauthorized);
        minter.disburse(0, 0, 0, bytes32(0));
        vm.expectRevert(unauthorized);
        minter.reverseDisburse(0, 0, bytes32(0), 0);
        vm.expectRevert(unauthorized);
        minter.reverseRepay(0, 0, bytes32(0));
        vm.expectRevert(unauthorized);
        minter.settleWireOut(0, 0, 0, bytes32(0));
        vm.expectRevert(unauthorized);
        minter.cancelWireOut(0);
        vm.expectRevert(unauthorized);
        minter.openRamp(MinterUpgradeable.RampDirection.BankToUsdc, 0, bytes32(0));
        vm.expectRevert(unauthorized);
        minter.closeRamp(0, 0, bytes32(0));
        vm.expectRevert(unauthorized);
        minter.recordExpense(0, 0, bytes32(0));
        vm.expectRevert(unauthorized);
        minter.recordCorrection(0, bytes32(0), 0);
        vm.expectRevert(unauthorized);
        minter.correctVaultMint(0, bytes32(0));
        vm.expectRevert(unauthorized);
        minter.pause();
        vm.expectRevert(unauthorized);
        minter.unpause();
        vm.stopPrank();
    }

    function testFuzz_minterAdminAccess(address caller) public {
        vm.assume(caller != admin);

        address[] memory custodians = new address[](0);
        bytes memory unauthorized = abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller);

        vm.startPrank(caller);
        vm.expectRevert(unauthorized);
        minter.setTreasury(caller);
        vm.expectRevert(unauthorized);
        minter.setFactory(caller);
        vm.expectRevert(unauthorized);
        minter.setPocket(caller);
        vm.expectRevert(unauthorized);
        minter.setCustodians(custodians);
        vm.expectRevert(unauthorized);
        minter.increaseTxLimit(0);
        vm.expectRevert(unauthorized);
        minter.decreaseTxLimit(0);
        vm.expectRevert(unauthorized);
        minter.increaseWindowLimit(0);
        vm.expectRevert(unauthorized);
        minter.decreaseWindowLimit(0);
        vm.stopPrank();
    }

    function testFuzz_collateralTrusteeAccess(address caller) public {
        vm.assume(caller != collateralTrustee);

        CollateralRegistryUpgradeable.PledgeLot memory pledgeLot;
        CollateralRegistryUpgradeable.Location memory location;
        CollateralRegistryUpgradeable.Control memory control;
        bytes memory unauthorized = abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller);

        vm.startPrank(caller);
        vm.expectRevert(unauthorized);
        collateralRegistry.pledge(0, pledgeLot);
        vm.expectRevert(unauthorized);
        collateralRegistry.setHaircut(0, 0, 0);
        vm.expectRevert(unauthorized);
        collateralRegistry.setFloor(0, 0);
        vm.expectRevert(unauthorized);
        collateralRegistry.setStage(0, 0, CollateralRegistryUpgradeable.LotStage.Pledged, false, location);
        vm.expectRevert(unauthorized);
        collateralRegistry.setControl(0, 0, control);
        vm.expectRevert(unauthorized);
        collateralRegistry.addDoc(0, 0, CollateralRegistryUpgradeable.DocKind.Ebl, bytes32(0));
        vm.expectRevert(unauthorized);
        collateralRegistry.adjustQuantity(0, 0, 0, "", bytes32(0));
        vm.expectRevert(unauthorized);
        collateralRegistry.release(0, 0, 0, CollateralRegistryUpgradeable.ReleaseReason.Payment, bytes32(0));
        vm.expectRevert(unauthorized);
        collateralRegistry.liquidate(0, 0, 0);
        vm.expectRevert(unauthorized);
        collateralRegistry.pause();
        vm.expectRevert(unauthorized);
        collateralRegistry.unpause();
        vm.stopPrank();
    }

    function testFuzz_collateralValuerAccess(address caller) public {
        vm.assume(caller != collateralValuer);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        collateralRegistry.revalue(0, 0, 0, bytes32(0), bytes32(0));
    }

    function testFuzz_collateralAdminAccess(address caller) public {
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        collateralRegistry.setLoanRegistry(caller);
    }

    function testFuzz_dealTokenFactoryAccess(address caller) public {
        vm.assume(caller != loanRegistryManager);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        dealTokenFactory.registerDeal(0);
    }

    function testFuzz_dealTokenFactoryAdminAccess(address caller) public {
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        dealTokenFactory.setLoanRegistry(caller);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        dealTokenFactory.setCollateralRegistry(caller);
    }
}
