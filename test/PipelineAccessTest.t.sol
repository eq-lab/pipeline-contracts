// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {IAccessManaged} from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {WhitelistAccessedUpgradeable} from "../src/whitelist/WhitelistAccessedUpgradeable.sol";
import {ILoanRegistry} from "../src/interfaces/ILoanRegistry.sol";
import {MinterUpgradeable} from "../src/minter/MinterUpgradeable.sol";
import {ISecurityRecordNft} from "../src/interfaces/ISecurityRecordNft.sol";
import {ISecurityRegistry} from "../src/interfaces/ISecurityRegistry.sol";
import {SecurityRegistryUpgradeable} from "../src/securityRegistry/SecurityRegistryUpgradeable.sol";

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

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        UUPSUpgradeable(address(securityRecordNft)).upgradeToAndCall(address(securityRecordNft), "");
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
        loanRegistry.undisburse(0, 0);

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
        minter.recordWireIn(caller, 0, 0, bytes32(0));
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
        minter.assignWireIn(0, caller);
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

    function testFuzz_securityAgentAccess(address caller) public {
        vm.assume(caller != securityAgent);

        ISecurityRegistry.NewRecord memory newRecord;
        bytes memory unauthorized = abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller);

        vm.startPrank(caller);
        vm.expectRevert(unauthorized);
        securityRegistry.register(0, 0, newRecord);
        vm.expectRevert(unauthorized);
        securityRegistry.perfect(0, bytes32(0));
        vm.expectRevert(unauthorized);
        securityRegistry.handover(0, 0, bytes32(0));
        vm.expectRevert(unauthorized);
        securityRegistry.attest(0);
        vm.expectRevert(unauthorized);
        securityRecordNft.addDoc(0, ISecurityRecordNft.DocKind.Ebl, bytes32(0));
        vm.expectRevert(unauthorized);
        securityRegistry.release(0, bytes32(0));
        vm.expectRevert(unauthorized);
        securityRegistry.reportMandateBreach(0, bytes32(0));
        vm.expectRevert(unauthorized);
        securityRegistry.startEnforcement(0);
        vm.expectRevert(unauthorized);
        securityRegistry.markEnforced(0, bytes32(0));
        vm.stopPrank();
    }

    function testFuzz_securityRiskCouncilAccess(address caller) public {
        vm.assume(caller != securityRiskCouncil);

        ISecurityRegistry.Terms memory terms;
        bytes memory unauthorized = abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller);

        vm.startPrank(caller);
        vm.expectRevert(unauthorized);
        securityRegistry.setTerms(0, terms);
        vm.expectRevert(unauthorized);
        securityRegistry.releaseWithConsent(0, bytes32(0));
        vm.expectRevert(unauthorized);
        securityRegistry.resolveFlag(0, ISecurityRegistry.FlagOutcome.Accepted, bytes32(0));
        vm.expectRevert(unauthorized);
        securityRecordNft.setInspectors(new address[](0));
        vm.stopPrank();
    }

    function testFuzz_securityInspectionOperatorAccess(address caller) public {
        vm.assume(caller != securityInspectionOperator && caller != securityInspectionSecondOperator);

        ISecurityRecordNft.NewInspection memory newInspection;
        bytes memory unauthorized = abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller);

        vm.startPrank(caller);
        vm.expectRevert(unauthorized);
        securityRecordNft.recordInspection(0, newInspection);
        vm.expectRevert(unauthorized);
        securityRecordNft.approveInspection(0);
        vm.stopPrank();
    }

    function testFuzz_securityTrusteeAccess(address caller) public {
        vm.assume(caller != securityTrustee);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        securityRegistry.recordExtensionConsent(0, 0, bytes32(0));
    }

    function testFuzz_securityValuerAccess(address caller) public {
        vm.assume(caller != securityValuer);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        securityRegistry.revalue(0, 0, bytes32(0), bytes32(0));
    }

    function testFuzz_securityPauserAccess(address caller) public {
        vm.assume(caller != pauser);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        securityRegistry.pause();

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        securityRegistry.unpause();
    }

    function testFuzz_securityAdminAccess(address caller) public {
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        securityRegistry.setLoanRegistry(caller);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        securityRecordNft.setSecurityRegistry(caller);
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
    }
}
