// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {RateLimiterUpgradeable} from "../depositManager/RateLimiterUpgradeable.sol";
import {IDealTokenFactory} from "../interfaces/IDealTokenFactory.sol";
import {ILoanRegistry} from "../interfaces/ILoanRegistry.sol";
import {IPipelineUSD} from "../interfaces/IPipelineUSD.sol";
import {IPocket} from "../interfaces/IPocket.sol";
import {IStakedPipelineUSD} from "../interfaces/IStakedPipelineUSD.sol";

abstract contract MinterUpgradeable is RateLimiterUpgradeable, PausableUpgradeable {
    using SafeERC20 for IPipelineUSD;
    using SafeCast for uint256;
    using SafeCast for int256;

    enum WireInStatus {
        Direct,
        Escrowed,
        Assigned,
        Returned
    }

    enum WireOutStatus {
        Pending,
        Settled,
        Cancelled
    }

    enum RampDirection {
        UsdcToBank,
        BankToUsdc
    }

    enum CashReason {
        Disbursed,
        DisbursementReversed,
        Income,
        Expense,
        Correction
    }

    struct WireIn {
        WireInStatus status;
        uint256 amount;
    }

    struct WireOut {
        address lp;
        WireOutStatus status;
        uint256 amount;
    }

    struct Ramp {
        RampDirection direction;
        bool closed;
        uint256 amount;
    }

    struct Disbursement {
        uint256 loanId;
        uint256 amount;
        bool reversed;
    }

    struct Repayment {
        uint256 feeShares;
        uint256 fees;
        uint256 released;
        bool carvedOut;
    }

    struct AddressesConfig {
        address plUsd;
        address stakedPlUsd;
        address loanRegistry;
        address pocket;
        address usdc;
        address treasury;
        address factory;
    }

    event WireInRecorded(
        uint256 indexed id, address indexed receiver, uint256 amount, uint64 valueDate, bytes32 refHash
    );
    event WireInAssigned(uint256 indexed id, address indexed receiver);
    event WireInReturned(uint256 indexed id, uint256 amount, bytes32 refHash);
    event CashDisbursed(uint256 indexed loanId, uint256 entryId, uint256 amount, uint64 valueDate, bytes32 refHash);
    event CashDisbursementReversed(
        uint256 indexed loanId, uint256 entryId, uint256 originalId, uint256 amount, bytes32 refHash
    );
    event CashRepaid(
        uint256 indexed loanId,
        uint256 repaymentId,
        uint256 saleId,
        uint256 cash,
        uint256 interestMinted,
        uint256 feeShares,
        uint64 valueDate,
        bytes32 refHash
    );
    event CashRepaymentReversed(uint256 indexed loanId, uint256 repaymentId, uint256 cash, bytes32 refHash);
    event WireOutRequested(uint256 indexed id, address indexed lp, uint256 amount);
    event WireOutSettled(uint256 indexed id, uint256 amount, uint64 valueDate, bytes32 refHash);
    event WireOutCancelled(uint256 indexed id);
    event RampOpened(uint256 indexed id, RampDirection direction, uint256 amount, bytes32 refHash);
    event RampClosed(uint256 indexed id, uint256 received, uint256 loss, bytes32 refHash);
    event CashRecorded(CashReason indexed reason, uint256 entryId, int256 delta, uint64 valueDate, bytes32 refHash);
    event CashCorrected(uint256 indexed originalId, uint256 entryId, int256 delta, bytes32 reasonHash);
    event MintCorrected(uint256 amount, bytes32 refHash);
    event LossAbsorbed(uint256 requested, uint256 pulled);
    event TreasurySet(address treasury);
    event CustodiansSet(address[] custodians);

    error MinterZeroAddress();
    error MinterSameValue();
    error MinterInvalidAmount();
    error MinterMissingRef();
    error MinterRefHashSeen();
    error MinterInsufficientBankCash(uint256 amount, uint256 bankCash);
    error MinterNonExistentWireIn();
    error MinterNonExistentWireOut();
    error MinterNonExistentRamp();
    error MinterNonExistentCashEntry();
    error MinterWrongWireStatus();
    error MinterReceiverNotAllowed(address receiver);
    error MinterAmountMismatch(uint256 expected);
    error MinterInsufficientCustody(uint256 custody);
    error MinterReceivedExceedsAmount(uint256 amount);
    error MinterRampClosed();
    error MinterAlreadyReversed();
    error MinterWrongEntry();
    error MinterPulledMoreThanRequested(uint256 requested, uint256 pulled);

    /// @custom:storage-location erc7201:pipeline.storage.Minter
    struct MinterStorage {
        IPipelineUSD plUsd;
        IStakedPipelineUSD stakedPlUsd;
        ILoanRegistry loanRegistry;
        IPocket pocket;
        IERC20 usdc;
        address treasury;
        address factory;
        address[] custodians;
        uint256 bankCash;
        uint256 inFlight;
        uint256 unabsorbedTotal;
        uint256 nextWireInId;
        uint256 nextWireOutId;
        uint256 nextRampId;
        uint256 nextCashEntryId;
        mapping(uint256 id => WireIn) wiresIn;
        mapping(uint256 id => WireOut) wiresOut;
        mapping(uint256 id => Ramp) ramps;
        mapping(uint256 entryId => Disbursement) disbursements;
        mapping(uint256 loanId => mapping(uint256 repaymentId => Repayment)) repayments;
        mapping(bytes32 refHash => bool) refHashesSeen;
    }

    // keccak256(abi.encode(uint256(keccak256("pipeline.storage.Minter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MinterStorageLocation = 0x1cb61fb8c91dfac98430b399e1cf1804c4c3862229ec367a9bc71c2a7e5cc100;

    function _getMinterStorage() private pure returns (MinterStorage storage $) {
        assembly {
            $.slot := MinterStorageLocation
        }
    }

    function __Minter_init_unchained(
        address _stakedPlUsd,
        address _loanRegistry,
        address _treasury,
        address _factory,
        address _pocket,
        address _usdc
    ) internal onlyInitializing {
        if (_pocket == address(0) || _factory == address(0)) revert MinterZeroAddress();

        MinterStorage storage $ = _getMinterStorage();
        $.stakedPlUsd = IStakedPipelineUSD(_stakedPlUsd);
        $.plUsd = IPipelineUSD(IERC4626(_stakedPlUsd).asset());
        $.loanRegistry = ILoanRegistry(_loanRegistry);
        $.usdc = IERC20(_usdc);
        $.pocket = IPocket(_pocket);
        $.factory = _factory;

        _setTreasury($, _treasury);
    }

    function recordWireIn(address receiver, uint256 amount, uint64 valueDate, bytes32 refHash)
        external
        restricted
        whenNotPaused
        returns (uint256 id)
    {
        if (amount == 0) revert MinterInvalidAmount();

        MinterStorage storage $ = _getMinterStorage();
        _consumeMintRef($, refHash);
        _applyRateLimits(amount);
        $.bankCash += amount;
        _mintPlUsd($, address(this), amount);

        WireInStatus status = WireInStatus.Escrowed;
        if (receiver != address(this)) {
            _stakeFor($, receiver, amount);
            status = WireInStatus.Direct;
        }

        id = $.nextWireInId++;
        $.wiresIn[id] = WireIn({status: status, amount: amount});

        emit WireInRecorded(id, receiver, amount, valueDate, refHash);
    }

    function assignWireIn(uint256 id, address receiver) external restricted whenNotPaused {
        MinterStorage storage $ = _getMinterStorage();
        WireIn storage wire = _escrowedWireIn($, id);

        _stakeFor($, receiver, wire.amount);

        wire.status = WireInStatus.Assigned;

        emit WireInAssigned(id, receiver);
    }

    function returnWireIn(uint256 id, bytes32 refHash) external restricted {
        MinterStorage storage $ = _getMinterStorage();
        WireIn storage wire = _escrowedWireIn($, id);

        _consumeRef($, refHash);
        uint256 amount = wire.amount;
        _burnPlUsd($, amount);
        _subBankCash($, amount);

        wire.status = WireInStatus.Returned;

        emit WireInReturned(id, amount, refHash);
    }

    function disburse(uint256 loanId, uint256 amount, uint64 valueDate, bytes32 refHash)
        external
        restricted
        whenNotPaused
        returns (uint256 entryId)
    {
        if (amount == 0) revert MinterInvalidAmount();

        MinterStorage storage $ = _getMinterStorage();
        _consumeRef($, refHash);
        _subBankCash($, amount);

        $.loanRegistry.disburse(loanId, amount);
        _syncDebt($, loanId);

        entryId = $.nextCashEntryId++;
        $.disbursements[entryId] = Disbursement({loanId: loanId, amount: amount, reversed: false});

        emit CashDisbursed(loanId, entryId, amount, valueDate, refHash);
    }

    function reverseDisburse(uint256 loanId, uint256 amount, bytes32 refHash, uint256 originalId) external restricted {
        MinterStorage storage $ = _getMinterStorage();
        Disbursement storage original = _existingDisbursement($, originalId);
        if (original.loanId != loanId || original.amount != amount) revert MinterWrongEntry();
        if (original.reversed) revert MinterAlreadyReversed();

        _consumeRef($, refHash);
        $.bankCash += amount;

        $.loanRegistry.undisburse(loanId, amount);
        _syncDebt($, loanId);

        original.reversed = true;
        uint256 entryId = $.nextCashEntryId++;

        emit CashDisbursementReversed(loanId, entryId, originalId, amount, refHash);
    }

    function repay(
        uint256 loanId,
        ILoanRegistry.RepaymentData calldata repaymentData,
        uint64 valueDate,
        bytes32 refHash,
        uint256 saleId
    ) external restricted whenNotPaused returns (uint256 repaymentId) {
        if (repaymentData.offtakerReceived < repaymentData.equityDistributed) {
            revert MinterInvalidAmount();
        }

        uint256 cash = repaymentData.offtakerReceived - repaymentData.equityDistributed;
        uint256 interest = repaymentData.seniorInterest;
        uint256 fees = repaymentData.mgmtFee + repaymentData.perfFee + repaymentData.oetAlloc;

        MinterStorage storage $ = _getMinterStorage();
        _consumeMintRef($, refHash);
        if (interest + fees != 0) _applyRateLimits(interest + fees);
        $.bankCash += cash;

        bool carvedOut;
        (repaymentId, carvedOut) = $.loanRegistry.recordPayment(loanId, repaymentData);

        uint256 released;
        if (carvedOut) {
            IPocket _pocket = $.pocket;
            if (interest != 0) _mintPlUsd($, address(_pocket), interest);
            released = _pocket.release(loanId, repaymentData.seniorPrincipalRepaid, interest);
        } else if (interest != 0) {
            _mintPlUsd($, address($.stakedPlUsd), interest);
        }

        uint256 feeShares;
        if (fees != 0) {
            _mintPlUsd($, address(this), fees);
            feeShares = _stakeFor($, $.treasury, fees);
        }

        _syncDebt($, loanId);

        $.repayments[loanId][repaymentId] =
            Repayment({feeShares: feeShares, fees: fees, released: released, carvedOut: carvedOut});

        emit CashRepaid(loanId, repaymentId, saleId, cash, interest, feeShares, valueDate, refHash);
    }

    function reverseRepay(uint256 loanId, uint256 repaymentId, bytes32 refHash) external restricted {
        MinterStorage storage $ = _getMinterStorage();
        (uint256 principal, uint256 interest) = $.loanRegistry.unrecordPayment(loanId, repaymentId);

        Repayment storage record = $.repayments[loanId][repaymentId];
        uint256 fees = record.fees;
        uint256 cash = principal + interest + fees;
        _consumeRef($, refHash);
        _subBankCash($, cash);

        uint256 feeShares = record.feeShares;
        if (feeShares != 0) {
            uint256 assets = $.stakedPlUsd.burnShares($.treasury, feeShares);
            if (assets != 0) _burnPlUsd($, assets);
            if (assets < fees) _absorb($, fees - assets);
        }

        if (record.carvedOut) {
            $.pocket.unrelease(loanId, record.released, interest);
        } else {
            _absorb($, interest);
        }

        _syncDebt($, loanId);

        emit CashRepaymentReversed(loanId, repaymentId, cash, refHash);
    }

    function requestWireOut(uint256 amount) external whenNotPaused returns (uint256 id) {
        if (amount == 0) revert MinterInvalidAmount();

        MinterStorage storage $ = _getMinterStorage();
        $.plUsd.safeTransferFrom(msg.sender, address(this), amount);

        id = $.nextWireOutId++;
        $.wiresOut[id] = WireOut({lp: msg.sender, status: WireOutStatus.Pending, amount: amount});

        emit WireOutRequested(id, msg.sender, amount);
    }

    function settleWireOut(uint256 id, uint256 amount, uint64 valueDate, bytes32 refHash) external restricted {
        MinterStorage storage $ = _getMinterStorage();
        WireOut storage wire = _pendingWireOut($, id);
        if (amount != wire.amount) revert MinterAmountMismatch(wire.amount);

        _consumeRef($, refHash);
        _burnPlUsd($, amount);
        _subBankCash($, amount);

        wire.status = WireOutStatus.Settled;

        emit WireOutSettled(id, amount, valueDate, refHash);
    }

    function cancelWireOut(uint256 id) external restricted {
        MinterStorage storage $ = _getMinterStorage();
        WireOut storage wire = _pendingWireOut($, id);

        $.plUsd.safeTransfer(wire.lp, wire.amount);
        wire.status = WireOutStatus.Cancelled;

        emit WireOutCancelled(id);
    }

    function openRamp(RampDirection direction, uint256 amount, bytes32 refHash)
        external
        restricted
        whenNotPaused
        returns (uint256 id)
    {
        if (amount == 0) revert MinterInvalidAmount();

        MinterStorage storage $ = _getMinterStorage();
        _consumeRef($, refHash);

        if (direction == RampDirection.UsdcToBank) {
            uint256 custodyTotal = _custodyTotal($);
            if (custodyTotal < amount) revert MinterInsufficientCustody(custodyTotal);
        } else {
            _subBankCash($, amount);
        }
        $.inFlight += amount;

        id = $.nextRampId++;
        $.ramps[id] = Ramp({direction: direction, closed: false, amount: amount});

        emit RampOpened(id, direction, amount, refHash);
    }

    function closeRamp(uint256 id, uint256 received, bytes32 refHash) external restricted {
        MinterStorage storage $ = _getMinterStorage();
        Ramp storage rampData = _existingRamp($, id);
        if (rampData.closed) revert MinterRampClosed();

        uint256 amount = rampData.amount;
        if (received > amount) revert MinterReceivedExceedsAmount(amount);

        _consumeRef($, refHash);
        $.inFlight -= amount;
        if (rampData.direction == RampDirection.UsdcToBank) $.bankCash += received;

        uint256 loss = amount - received;
        if (loss != 0) {
            _absorb($, loss);
            _recordCash($, CashReason.Expense, -loss.toInt256(), uint64(block.timestamp), refHash);
        }

        rampData.closed = true;

        emit RampClosed(id, received, loss, refHash);
    }

    function recordIncome(uint256 delta, uint64 valueDate, bytes32 refHash) external restricted whenNotPaused {
        if (delta == 0) revert MinterInvalidAmount();

        MinterStorage storage $ = _getMinterStorage();
        _consumeMintRef($, refHash);
        _applyRateLimits(delta);
        $.bankCash += delta;
        _mintPlUsd($, address($.stakedPlUsd), delta);

        _recordCash($, CashReason.Income, delta.toInt256(), valueDate, refHash);
    }

    function recordExpense(uint256 delta, uint64 valueDate, bytes32 refHash) external restricted {
        if (delta == 0) revert MinterInvalidAmount();

        MinterStorage storage $ = _getMinterStorage();
        _consumeRef($, refHash);
        _subBankCash($, delta);
        _absorb($, delta);

        _recordCash($, CashReason.Expense, -delta.toInt256(), valueDate, refHash);
    }

    function recordCorrection(int256 delta, bytes32 reasonHash, uint256 originalId) external restricted {
        MinterStorage storage $ = _getMinterStorage();
        _requireCashEntry($, originalId);

        uint256 _bankCash = $.bankCash;
        int256 updated = _bankCash.toInt256() + delta;
        if (updated < 0) revert MinterInsufficientBankCash((-delta).toUint256(), _bankCash);
        $.bankCash = updated.toUint256();

        emit CashCorrected(originalId, $.nextCashEntryId++, delta, reasonHash);
    }

    function correctVaultMint(uint256 amount, bytes32 refHash) external restricted {
        if (amount == 0) revert MinterInvalidAmount();

        MinterStorage storage $ = _getMinterStorage();
        _consumeRef($, refHash);
        _absorb($, amount);

        emit MintCorrected(amount, refHash);
    }

    function setTreasury(address newTreasury) external restricted {
        _setTreasury(_getMinterStorage(), newTreasury);
    }

    function setCustodians(address[] calldata newCustodians) external restricted {
        for (uint256 i; i < newCustodians.length; ++i) {
            if (newCustodians[i] == address(0)) revert MinterZeroAddress();
        }
        _getMinterStorage().custodians = newCustodians;

        emit CustodiansSet(newCustodians);
    }

    function pause() external restricted {
        _pause();
    }

    function unpause() external restricted {
        _unpause();
    }

    function addressesConfig() external view returns (AddressesConfig memory) {
        MinterStorage storage $ = _getMinterStorage();
        return AddressesConfig({
            plUsd: address($.plUsd),
            stakedPlUsd: address($.stakedPlUsd),
            loanRegistry: address($.loanRegistry),
            pocket: address($.pocket),
            usdc: address($.usdc),
            treasury: $.treasury,
            factory: $.factory
        });
    }

    function custodians() external view returns (address[] memory) {
        return _getMinterStorage().custodians;
    }

    function bankCash() external view returns (uint256) {
        return _getMinterStorage().bankCash;
    }

    function inFlight() external view returns (uint256) {
        return _getMinterStorage().inFlight;
    }

    function unabsorbedTotal() external view returns (uint256) {
        return _getMinterStorage().unabsorbedTotal;
    }

    function wireIn(uint256 id) external view returns (WireIn memory) {
        return _existingWireIn(_getMinterStorage(), id);
    }

    function wireOut(uint256 id) external view returns (WireOut memory) {
        return _existingWireOut(_getMinterStorage(), id);
    }

    function ramp(uint256 id) external view returns (Ramp memory) {
        return _existingRamp(_getMinterStorage(), id);
    }

    function disbursement(uint256 entryId) external view returns (Disbursement memory) {
        return _existingDisbursement(_getMinterStorage(), entryId);
    }

    function repayment(uint256 loanId, uint256 repaymentId) external view returns (Repayment memory) {
        return _getMinterStorage().repayments[loanId][repaymentId];
    }

    function refHashSeen(bytes32 refHash) external view returns (bool) {
        return _getMinterStorage().refHashesSeen[refHash];
    }

    function _setTreasury(MinterStorage storage $, address newTreasury) private {
        if (newTreasury == address(0)) revert MinterZeroAddress();
        if ($.treasury == newTreasury) revert MinterSameValue();
        $.treasury = newTreasury;

        emit TreasurySet(newTreasury);
    }

    function _consumeRef(MinterStorage storage $, bytes32 refHash) private {
        if (refHash == bytes32(0)) return;
        if ($.refHashesSeen[refHash]) revert MinterRefHashSeen();
        $.refHashesSeen[refHash] = true;
    }

    function _consumeMintRef(MinterStorage storage $, bytes32 refHash) private {
        if (refHash == bytes32(0)) revert MinterMissingRef();
        _consumeRef($, refHash);
    }

    function _mintPlUsd(MinterStorage storage $, address to, uint256 amount) private {
        $.plUsd.mint(to, amount);
    }

    function _burnPlUsd(MinterStorage storage $, uint256 amount) private {
        $.plUsd.burn(amount);
    }

    function _subBankCash(MinterStorage storage $, uint256 amount) private {
        uint256 _bankCash = $.bankCash;
        if (amount > _bankCash) revert MinterInsufficientBankCash(amount, _bankCash);
        $.bankCash = _bankCash - amount;
    }

    function _stakeFor(MinterStorage storage $, address receiver, uint256 amount) private returns (uint256 shares) {
        IPipelineUSD _plUsd = $.plUsd;
        if (!_plUsd.hasAccess(receiver)) revert MinterReceiverNotAllowed(receiver);

        IStakedPipelineUSD _stakedPlUsd = $.stakedPlUsd;
        _plUsd.forceApprove(address(_stakedPlUsd), amount);
        return _stakedPlUsd.deposit(amount, receiver);
    }

    function _absorb(MinterStorage storage $, uint256 amount) private {
        if (amount == 0) return;

        uint256 pulled = $.stakedPlUsd.pull(amount);
        if (pulled > amount) revert MinterPulledMoreThanRequested(amount, pulled);
        if (pulled != 0) _burnPlUsd($, pulled);
        $.unabsorbedTotal += amount - pulled;

        emit LossAbsorbed(amount, pulled);
    }

    function _syncDebt(MinterStorage storage $, uint256 loanId) private {
        IDealTokenFactory($.factory).syncDebt(loanId);
    }

    function _recordCash(MinterStorage storage $, CashReason reason, int256 delta, uint64 valueDate, bytes32 refHash)
        private
    {
        emit CashRecorded(reason, $.nextCashEntryId++, delta, valueDate, refHash);
    }

    function _custodyTotal(MinterStorage storage $) private view returns (uint256 total) {
        address[] storage _custodians = $.custodians;
        IERC20 _usdc = $.usdc;

        for (uint256 i; i < _custodians.length; ++i) {
            try _usdc.balanceOf(_custodians[i]) returns (uint256 balance) {
                total += balance;
            } catch {}
        }
    }

    function _existingWireIn(MinterStorage storage $, uint256 id) private view returns (WireIn storage) {
        if (id >= $.nextWireInId) revert MinterNonExistentWireIn();
        return $.wiresIn[id];
    }

    function _escrowedWireIn(MinterStorage storage $, uint256 id) private view returns (WireIn storage wire) {
        wire = _existingWireIn($, id);
        if (wire.status != WireInStatus.Escrowed) revert MinterWrongWireStatus();
    }

    function _existingWireOut(MinterStorage storage $, uint256 id) private view returns (WireOut storage) {
        if (id >= $.nextWireOutId) revert MinterNonExistentWireOut();
        return $.wiresOut[id];
    }

    function _pendingWireOut(MinterStorage storage $, uint256 id) private view returns (WireOut storage wire) {
        wire = _existingWireOut($, id);
        if (wire.status != WireOutStatus.Pending) revert MinterWrongWireStatus();
    }

    function _existingRamp(MinterStorage storage $, uint256 id) private view returns (Ramp storage) {
        if (id >= $.nextRampId) revert MinterNonExistentRamp();
        return $.ramps[id];
    }

    function _requireCashEntry(MinterStorage storage $, uint256 id) private view {
        if (id >= $.nextCashEntryId) revert MinterNonExistentCashEntry();
    }

    function _existingDisbursement(MinterStorage storage $, uint256 entryId)
        private
        view
        returns (Disbursement storage entry)
    {
        _requireCashEntry($, entryId);
        entry = $.disbursements[entryId];
        if (entry.amount == 0) revert MinterWrongEntry();
    }
}
