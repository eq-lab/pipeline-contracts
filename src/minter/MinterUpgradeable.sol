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
        address receiver;
        WireInStatus status;
        uint64 valueDate;
        uint256 amount;
        bytes32 refHash;
        bytes32 lpRef;
        bytes32 returnRef;
    }

    struct WireOut {
        address lp;
        WireOutStatus status;
        uint64 requestedAt;
        uint256 amount;
        bytes32 refHash;
    }

    struct Ramp {
        RampDirection direction;
        bool closed;
        uint64 openedAt;
        uint64 closedAt;
        uint256 amount;
        uint256 received;
    }

    struct CashEntry {
        int256 delta;
        CashReason reason;
        bool reversed;
        uint64 valueDate;
        uint256 loanId;
        uint256 original;
        bytes32 refHash;
    }

    struct Repayment {
        uint256 cash;
        uint256 principal;
        uint256 interestMinted;
        uint256 feeShares;
        uint256 saleId;
        bool carvedOut;
        bool reversed;
        bool recorded;
    }

    struct Custody {
        address custodian;
        uint256 balance;
    }

    struct PoolState {
        Custody[] custody;
        bool readFailed;
        uint256 bankCash;
        uint256 inFlight;
        uint256 outstandingTotal;
        uint256 unabsorbedTotal;
        uint256 totalAssets;
    }

    event WireInRecorded(
        uint256 indexed id, address indexed receiver, uint256 amount, uint64 valueDate, bytes32 refHash, bytes32 lpRef
    );
    event WireInAssigned(uint256 indexed id, address indexed receiver, bytes32 lpRef);
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
    event MintCorrected(uint256 amount, bytes32 refHash);
    event LossAbsorbed(uint256 requested, uint256 pulled);
    event SyncLagging(uint256 indexed loanId);
    event Snapshot(uint256 indexed blockNumber, PoolState pool);
    event TreasurySet(address treasury);
    event FactorySet(address factory);
    event PocketSet(address pocket);
    event CustodiansSet(address[] custodians);

    error MinterZeroAddress();
    error MinterSameValue();
    error MinterInvalidAmount();
    error MinterMissingRef();
    error MinterRefHashSeen(bytes32 refHash);
    error MinterInsufficientBankCash(uint256 amount, uint256 bankCash);
    error MinterNonExistentWireIn(uint256 id);
    error MinterNonExistentWireOut(uint256 id);
    error MinterNonExistentRamp(uint256 id);
    error MinterNonExistentCashEntry(uint256 id);
    error MinterNonExistentRepayment(uint256 loanId, uint256 repaymentId);
    error MinterWrongWireStatus(uint256 id);
    error MinterReceiverNotAllowed(address receiver);
    error MinterAmountMismatch(uint256 amount, uint256 expected);
    error MinterInsufficientCustody(uint256 amount, uint256 custody);
    error MinterReceivedExceedsAmount(uint256 received, uint256 amount);
    error MinterRampClosed(uint256 id);
    error MinterAlreadyReversed();
    error MinterWrongEntry(uint256 entryId);
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
        mapping(uint256 id => CashEntry) cashEntries;
        mapping(uint256 entryId => uint256) disbursementIndices;
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
        MinterStorage storage $ = _getMinterStorage();
        $.stakedPlUsd = IStakedPipelineUSD(_stakedPlUsd);
        $.plUsd = IPipelineUSD(IERC4626(_stakedPlUsd).asset());
        $.loanRegistry = ILoanRegistry(_loanRegistry);
        $.usdc = IERC20(_usdc);
        $.factory = _factory;

        _setTreasury($, _treasury);
        _setPocket($, _pocket);

        emit FactorySet(_factory);
    }

    function recordWireIn(address receiver, uint256 amount, uint64 valueDate, bytes32 refHash, bytes32 lpRef)
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
        $.plUsd.mint(address(this), amount);

        WireInStatus status = WireInStatus.Escrowed;
        if (receiver != address(this)) {
            _stakeFor($, receiver, amount);
            status = WireInStatus.Direct;
        }

        id = $.nextWireInId++;
        $.wiresIn[id] = WireIn({
            receiver: receiver,
            status: status,
            valueDate: valueDate,
            amount: amount,
            refHash: refHash,
            lpRef: lpRef,
            returnRef: bytes32(0)
        });

        emit WireInRecorded(id, receiver, amount, valueDate, refHash, lpRef);
    }

    function assignWireIn(uint256 id, address receiver, bytes32 lpRef) external restricted whenNotPaused {
        MinterStorage storage $ = _getMinterStorage();
        WireIn storage wire = _escrowedWireIn($, id);

        _stakeFor($, receiver, wire.amount);

        wire.status = WireInStatus.Assigned;
        wire.receiver = receiver;
        wire.lpRef = lpRef;

        emit WireInAssigned(id, receiver, lpRef);
    }

    function returnWireIn(uint256 id, bytes32 refHash) external restricted {
        MinterStorage storage $ = _getMinterStorage();
        WireIn storage wire = _escrowedWireIn($, id);

        _consumeRef($, refHash);
        uint256 amount = wire.amount;
        $.plUsd.burn(amount);
        _subBankCash($, amount);

        wire.status = WireInStatus.Returned;
        wire.returnRef = refHash;

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

        uint256 index = $.loanRegistry.disburse(loanId, amount);
        _syncDebt($, loanId);

        entryId = _newCashEntry($, -amount.toInt256(), CashReason.Disbursed, valueDate, refHash, loanId, 0);
        $.disbursementIndices[entryId] = index;

        emit CashDisbursed(loanId, entryId, amount, valueDate, refHash);
    }

    function reverseDisburse(uint256 loanId, uint256 amount, bytes32 refHash, uint256 originalId) external restricted {
        MinterStorage storage $ = _getMinterStorage();
        CashEntry storage original = _existingCashEntry($, originalId);
        if (
            original.reason != CashReason.Disbursed || original.loanId != loanId || original.delta != -amount.toInt256()
        ) {
            revert MinterWrongEntry(originalId);
        }
        if (original.reversed) revert MinterAlreadyReversed();

        _consumeRef($, refHash);
        $.bankCash += amount;

        $.loanRegistry.undisburse(loanId, $.disbursementIndices[originalId], amount);
        _syncDebt($, loanId);

        original.reversed = true;
        uint256 entryId = _newCashEntry(
            $, amount.toInt256(), CashReason.DisbursementReversed, uint64(block.timestamp), refHash, loanId, originalId
        );

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

        ILoanRegistry _loanRegistry = $.loanRegistry;
        repaymentId = _loanRegistry.recordPayment(loanId, repaymentData);

        uint256 principal = repaymentData.seniorPrincipalRepaid;
        bool carvedOut = _loanRegistry.loanMoney(loanId).carvedOut;
        if (carvedOut) {
            IPocket _pocket = $.pocket;
            if (interest != 0) $.plUsd.mint(address(_pocket), interest);
            principal = _pocket.release(loanId, principal, interest);
        } else if (interest != 0) {
            $.plUsd.mint(address($.stakedPlUsd), interest);
        }

        uint256 feeShares;
        if (fees != 0) {
            $.plUsd.mint(address(this), fees);
            feeShares = _stakeFor($, $.treasury, fees);
        }

        _syncDebt($, loanId);

        $.repayments[loanId][repaymentId] = Repayment({
            cash: cash,
            principal: principal,
            interestMinted: interest,
            feeShares: feeShares,
            saleId: saleId,
            carvedOut: carvedOut,
            reversed: false,
            recorded: true
        });

        emit CashRepaid(loanId, repaymentId, saleId, cash, interest, feeShares, valueDate, refHash);
    }

    function reverseRepay(uint256 loanId, uint256 repaymentId, bytes32 refHash) external restricted {
        MinterStorage storage $ = _getMinterStorage();
        Repayment storage record = _existingRepayment($, loanId, repaymentId);
        if (record.reversed) revert MinterAlreadyReversed();

        _consumeRef($, refHash);
        _subBankCash($, record.cash);

        ILoanRegistry.RepaymentData memory repaymentData = $.loanRegistry.unrecordPayment(loanId, repaymentId);

        uint256 feeShares = record.feeShares;
        if (feeShares != 0) {
            uint256 assets = $.stakedPlUsd.burnShares($.treasury, feeShares);
            if (assets != 0) $.plUsd.burn(assets);

            uint256 fees = repaymentData.mgmtFee + repaymentData.perfFee + repaymentData.oetAlloc;
            if (assets < fees) _absorb($, fees - assets);
        }

        if (record.carvedOut) {
            $.pocket.unrelease(loanId, record.principal, record.interestMinted);
        } else {
            _absorb($, record.interestMinted);
        }

        _syncDebt($, loanId);

        record.reversed = true;

        emit CashRepaymentReversed(loanId, repaymentId, record.cash, refHash);
    }

    function requestWireOut(uint256 amount) external whenNotPaused returns (uint256 id) {
        if (amount == 0) revert MinterInvalidAmount();

        MinterStorage storage $ = _getMinterStorage();
        $.plUsd.safeTransferFrom(msg.sender, address(this), amount);

        id = $.nextWireOutId++;
        $.wiresOut[id] = WireOut({
            lp: msg.sender,
            status: WireOutStatus.Pending,
            requestedAt: uint64(block.timestamp),
            amount: amount,
            refHash: bytes32(0)
        });

        emit WireOutRequested(id, msg.sender, amount);
    }

    function settleWireOut(uint256 id, uint256 amount, uint64 valueDate, bytes32 refHash) external restricted {
        MinterStorage storage $ = _getMinterStorage();
        WireOut storage wire = _pendingWireOut($, id);
        if (amount != wire.amount) revert MinterAmountMismatch(amount, wire.amount);

        _consumeRef($, refHash);
        $.plUsd.burn(amount);
        _subBankCash($, amount);

        wire.status = WireOutStatus.Settled;
        wire.refHash = refHash;

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
            (,, uint256 custodyTotal) = _custody($);
            if (custodyTotal < amount) revert MinterInsufficientCustody(amount, custodyTotal);
        } else {
            _subBankCash($, amount);
        }
        $.inFlight += amount;

        id = $.nextRampId++;
        $.ramps[id] = Ramp({
            direction: direction,
            closed: false,
            openedAt: uint64(block.timestamp),
            closedAt: 0,
            amount: amount,
            received: 0
        });

        emit RampOpened(id, direction, amount, refHash);
    }

    function closeRamp(uint256 id, uint256 received, bytes32 refHash) external restricted {
        MinterStorage storage $ = _getMinterStorage();
        Ramp storage rampData = _existingRamp($, id);
        if (rampData.closed) revert MinterRampClosed(id);

        uint256 amount = rampData.amount;
        if (received > amount) revert MinterReceivedExceedsAmount(received, amount);

        _consumeRef($, refHash);
        $.inFlight -= amount;
        if (rampData.direction == RampDirection.UsdcToBank) $.bankCash += received;

        uint256 loss = amount - received;
        if (loss != 0) {
            _absorb($, loss);
            _newCashEntry($, -loss.toInt256(), CashReason.Expense, uint64(block.timestamp), refHash, 0, 0);
        }

        rampData.closed = true;
        rampData.closedAt = uint64(block.timestamp);
        rampData.received = received;

        emit RampClosed(id, received, loss, refHash);
    }

    function recordIncome(uint256 delta, uint64 valueDate, bytes32 refHash) external restricted whenNotPaused {
        if (delta == 0) revert MinterInvalidAmount();

        MinterStorage storage $ = _getMinterStorage();
        _consumeMintRef($, refHash);
        _applyRateLimits(delta);
        $.bankCash += delta;
        $.plUsd.mint(address($.stakedPlUsd), delta);

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
        _existingCashEntry($, originalId);

        uint256 _bankCash = $.bankCash;
        int256 updated = _bankCash.toInt256() + delta;
        if (updated < 0) revert MinterInsufficientBankCash((-delta).toUint256(), _bankCash);
        $.bankCash = updated.toUint256();

        uint256 entryId =
            _newCashEntry($, delta, CashReason.Correction, uint64(block.timestamp), reasonHash, 0, originalId);

        emit CashRecorded(CashReason.Correction, entryId, delta, uint64(block.timestamp), reasonHash);
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

    function setFactory(address newFactory) external restricted {
        MinterStorage storage $ = _getMinterStorage();
        if ($.factory == newFactory) revert MinterSameValue();
        $.factory = newFactory;

        emit FactorySet(newFactory);
    }

    function setPocket(address newPocket) external restricted {
        _setPocket(_getMinterStorage(), newPocket);
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

    function snapshot() external {
        emit Snapshot(block.number, poolState());
    }

    function plUsd() external view returns (address) {
        return address(_getMinterStorage().plUsd);
    }

    function stakedPlUsd() external view returns (address) {
        return address(_getMinterStorage().stakedPlUsd);
    }

    function loanRegistry() external view returns (address) {
        return address(_getMinterStorage().loanRegistry);
    }

    function pocket() external view returns (address) {
        return address(_getMinterStorage().pocket);
    }

    function usdc() external view returns (address) {
        return address(_getMinterStorage().usdc);
    }

    function treasury() external view returns (address) {
        return _getMinterStorage().treasury;
    }

    function factory() external view returns (address) {
        return _getMinterStorage().factory;
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

    function cashEntry(uint256 id) external view returns (CashEntry memory) {
        return _existingCashEntry(_getMinterStorage(), id);
    }

    function repayment(uint256 loanId, uint256 repaymentId) external view returns (Repayment memory) {
        return _existingRepayment(_getMinterStorage(), loanId, repaymentId);
    }

    function refHashSeen(bytes32 refHash) external view returns (bool) {
        return _getMinterStorage().refHashesSeen[refHash];
    }

    function totalAssets() external view returns (uint256) {
        return poolState().totalAssets;
    }

    function poolState() public view returns (PoolState memory pool) {
        MinterStorage storage $ = _getMinterStorage();
        ILoanRegistry _loanRegistry = $.loanRegistry;

        uint256 custodyTotal;
        (pool.custody, pool.readFailed, custodyTotal) = _custody($);
        pool.bankCash = $.bankCash;
        pool.inFlight = $.inFlight;
        pool.outstandingTotal = _loanRegistry.outstandingTotal();
        pool.unabsorbedTotal = $.unabsorbedTotal + _loanRegistry.unabsorbedTotal();
        pool.totalAssets = custodyTotal + pool.bankCash + pool.inFlight + pool.outstandingTotal;
    }

    function _setTreasury(MinterStorage storage $, address newTreasury) private {
        if (newTreasury == address(0)) revert MinterZeroAddress();
        if ($.treasury == newTreasury) revert MinterSameValue();
        $.treasury = newTreasury;

        emit TreasurySet(newTreasury);
    }

    function _setPocket(MinterStorage storage $, address newPocket) private {
        if (newPocket == address(0)) revert MinterZeroAddress();
        if (address($.pocket) == newPocket) revert MinterSameValue();
        $.pocket = IPocket(newPocket);

        emit PocketSet(newPocket);
    }

    function _consumeRef(MinterStorage storage $, bytes32 refHash) private {
        if (refHash == bytes32(0)) return;
        if ($.refHashesSeen[refHash]) revert MinterRefHashSeen(refHash);
        $.refHashesSeen[refHash] = true;
    }

    function _consumeMintRef(MinterStorage storage $, bytes32 refHash) private {
        if (refHash == bytes32(0)) revert MinterMissingRef();
        _consumeRef($, refHash);
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
        if (pulled != 0) $.plUsd.burn(pulled);
        $.unabsorbedTotal += amount - pulled;

        emit LossAbsorbed(amount, pulled);
    }

    function _syncDebt(MinterStorage storage $, uint256 loanId) private {
        address _factory = $.factory;
        if (_factory == address(0)) return;

        try IDealTokenFactory(_factory).syncDebt(loanId) {}
        catch {
            emit SyncLagging(loanId);
        }
    }

    function _newCashEntry(
        MinterStorage storage $,
        int256 delta,
        CashReason reason,
        uint64 valueDate,
        bytes32 refHash,
        uint256 loanId,
        uint256 original
    ) private returns (uint256 entryId) {
        entryId = $.nextCashEntryId++;
        $.cashEntries[entryId] = CashEntry({
            delta: delta,
            reason: reason,
            reversed: false,
            valueDate: valueDate,
            loanId: loanId,
            original: original,
            refHash: refHash
        });
    }

    function _recordCash(MinterStorage storage $, CashReason reason, int256 delta, uint64 valueDate, bytes32 refHash)
        private
    {
        uint256 entryId = _newCashEntry($, delta, reason, valueDate, refHash, 0, 0);

        emit CashRecorded(reason, entryId, delta, valueDate, refHash);
    }

    function _custody(MinterStorage storage $)
        private
        view
        returns (Custody[] memory custody, bool readFailed, uint256 total)
    {
        address[] storage _custodians = $.custodians;
        IERC20 _usdc = $.usdc;

        custody = new Custody[](_custodians.length);
        for (uint256 i; i < _custodians.length; ++i) {
            address custodian = _custodians[i];
            uint256 balance;
            try _usdc.balanceOf(custodian) returns (uint256 value) {
                balance = value;
            } catch {
                readFailed = true;
            }
            custody[i] = Custody({custodian: custodian, balance: balance});
            total += balance;
        }
    }

    function _existingWireIn(MinterStorage storage $, uint256 id) private view returns (WireIn storage) {
        if (id >= $.nextWireInId) revert MinterNonExistentWireIn(id);
        return $.wiresIn[id];
    }

    function _escrowedWireIn(MinterStorage storage $, uint256 id) private view returns (WireIn storage wire) {
        wire = _existingWireIn($, id);
        if (wire.status != WireInStatus.Escrowed) revert MinterWrongWireStatus(id);
    }

    function _existingWireOut(MinterStorage storage $, uint256 id) private view returns (WireOut storage) {
        if (id >= $.nextWireOutId) revert MinterNonExistentWireOut(id);
        return $.wiresOut[id];
    }

    function _pendingWireOut(MinterStorage storage $, uint256 id) private view returns (WireOut storage wire) {
        wire = _existingWireOut($, id);
        if (wire.status != WireOutStatus.Pending) revert MinterWrongWireStatus(id);
    }

    function _existingRamp(MinterStorage storage $, uint256 id) private view returns (Ramp storage) {
        if (id >= $.nextRampId) revert MinterNonExistentRamp(id);
        return $.ramps[id];
    }

    function _existingCashEntry(MinterStorage storage $, uint256 id) private view returns (CashEntry storage) {
        if (id >= $.nextCashEntryId) revert MinterNonExistentCashEntry(id);
        return $.cashEntries[id];
    }

    function _existingRepayment(MinterStorage storage $, uint256 loanId, uint256 repaymentId)
        private
        view
        returns (Repayment storage record)
    {
        record = $.repayments[loanId][repaymentId];
        if (!record.recorded) revert MinterNonExistentRepayment(loanId, repaymentId);
    }
}
