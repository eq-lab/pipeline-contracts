// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    ERC721PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {ILoanRegistry} from "../interfaces/ILoanRegistry.sol";
import {IStakedPipelineUSD} from "../interfaces/IStakedPipelineUSD.sol";
import {IPocket} from "../interfaces/IPocket.sol";

abstract contract LoanRegistryUpgradeable is ERC721PausableUpgradeable, ILoanRegistry {
    using SafeCast for uint256;
    using SafeCast for int256;

    uint256 public constant ONE = 1_000_000;
    uint256 public constant YEAR = 31557600;
    uint256 public constant BPS_ONE = 10_000;

    event LoanDrawn(uint256 indexed loanId, string metadataURI);
    event StatusUpdated(uint256 indexed loanId, LoanStatus indexed newStatus);
    event Disbursed(uint256 indexed loanId, uint256 amount, uint256 outstanding);
    event Undisbursed(uint256 indexed loanId, uint256 amount, uint256 outstanding);
    event PaymentRecorded(
        uint256 indexed loanId, uint256 indexed repaymentId, RepaymentData repayment, uint256 outstanding
    );
    event PaymentUnrecorded(
        uint256 indexed loanId, uint256 indexed repaymentId, RepaymentData repayment, uint256 outstanding
    );
    event LoanDefaulted(uint256 indexed loanId, uint256 outstanding, uint256 moved);
    event LoanWrittenDown(
        uint256 indexed loanId, uint256 amount, uint256 outstanding, uint256 burned, uint256 unabsorbed
    );
    event InterestAdjusted(uint256 indexed loanId, int256 delta, bytes32 reasonHash);
    event InterestSettled(uint256 indexed loanId, uint256 accrued, uint256 paid, uint256 waived);
    event LoanClosed(uint256 indexed loanId, ClosureReason indexed reason);
    event LoanRolledOver(uint256 indexed loanId, uint32 newRate, uint64 newMaturityTimestamp);
    event EconomicsAmended(uint256 indexed loanId, uint32 newRate, uint64 newMaturityTimestamp);
    event CapitalWalletSet(address capitalWallet);
    event StakedPlUsdSet(address stakedPlUsd);
    event PocketSet(address pocket);
    event MaxFeeBpsSet(uint32 maxFeeBps);
    event MaxResidualSet(uint256 maxResidual);

    error LoanRegistryNonExistentLoanId(uint256 loanId);
    error LoanRegistryAlreadyClosed(uint256 loanId);
    error LoanRegistryWrongCurrentStatus(uint256 loanId, LoanStatus currentStatus);
    error LoanRegistryNonTransferrable();
    error LoanRegistryWrongRepaymentData();
    error LoanRegistryNonExistentRepayment(uint256 loanId, uint256 repaymentId);
    error LoanRegistryInterestExceedsMax(uint256 loanId, uint256 seniorInterest, uint256 maxInterest);
    error LoanRegistryInvalidTranches();
    error LoanRegistryInvalidMaturityDate();
    error LoanRegistryInvalidOfftakerPrice();
    error LoanRegistryNotMatured(uint256 loanId);
    error LoanRegistryOfftakerExceedsPrice(
        uint256 loanId, uint256 cumulativeOfftakerReceived, uint256 originalOfftakerPrice
    );
    error LoanRegistryDisbursementExceedsTranche(uint256 loanId, uint256 disbursed, uint256 originalSeniorTranche);
    error LoanRegistryNonExistentDisbursement(uint256 loanId, uint256 index);
    error LoanRegistryAmountExceedsRemaining(uint256 loanId, uint256 index, uint256 amount, uint256 remaining);
    error LoanRegistryAmountExceedsOutstanding(uint256 loanId, uint256 amount, uint256 outstanding);
    error LoanRegistryRepaidExceedsDisbursed(uint256 loanId, uint256 repaidAndWrittenDown, uint256 disbursed);
    error LoanRegistryFeesExceedCap(uint256 loanId, uint256 fees, uint256 feeCap);
    error LoanRegistryNonZeroOnDefault(uint256 loanId);
    error LoanRegistryRepaymentAlreadyReversed(uint256 loanId, uint256 repaymentId);
    error LoanRegistryCarvedOut(uint256 loanId);
    error LoanRegistryOutstandingNotZero(uint256 loanId);
    error LoanRegistryResidualExceedsMax(uint256 loanId, uint256 residual, uint256 maxResidual);
    error LoanRegistryInvalidClosureReason(ClosureReason reason);
    error LoanRegistryInvalidAmount();
    error LoanRegistryInvalidMaxFeeBps();
    error LoanRegistryNotConfigured();
    error LoanRegistryCounterpartOverreported(uint256 requested, uint256 reported);
    error LoanRegistryZeroAddress();
    error LoanRegistrySameValue();

    /// @custom:storage-location erc7201:pipeline.storage.LoanRegistry
    struct LoanRegistryStorage {
        uint256 nextLoanId;
        address capitalWallet;
        IStakedPipelineUSD stakedPlUsd;
        IPocket pocket;
        uint32 maxFeeBps;
        uint256 maxResidual;
        uint256 outstandingTotal;
        uint256 unabsorbedTotal;
        mapping(uint256 loanId => ImmutableLoanData) immutableLoanData;
        mapping(uint256 loanId => MutableLoanData) mutableLoanData;
        mapping(uint256 loanId => RepaymentData) cumulativeRepaymentData;
        mapping(uint256 loanId => mapping(uint256 repaymentId => RepaymentData)) repaymentData;
        mapping(uint256 loanId => mapping(uint256 repaymentId => bool)) reversedRepayments;
        mapping(uint256 loanId => Disbursement[]) disbursements;
        mapping(uint256 loanId => mapping(uint256 epochId => EconomicsEpoch)) economicsEpochs;
    }

    // keccak256(abi.encode(uint256(keccak256("pipeline.storage.LoanRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant LoanRegistryStorageLocation =
        0x0e83a2630ccddfd2ad45e4ed21bf1275e7a3fac47a3296c919cdc663065e5e00;

    function _getLoanRegistryStorage() private pure returns (LoanRegistryStorage storage $) {
        assembly {
            $.slot := LoanRegistryStorageLocation
        }
    }

    function __LoanRegistry_init(string calldata erc721name, string calldata erc721symbol) internal onlyInitializing {
        __ERC721_init(erc721name, erc721symbol);
        __LoanRegistry_init_unchained();
    }

    function __LoanRegistry_init_unchained() internal onlyInitializing {}

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return _getLoanRegistryStorage().mutableLoanData[tokenId].metadataURI;
    }

    function approve(address, uint256) public pure override {
        revert LoanRegistryNonTransferrable();
    }

    function setApprovalForAll(address, bool) public pure override {
        revert LoanRegistryNonTransferrable();
    }

    function nextLoanId() external view returns (uint256) {
        return _getLoanRegistryStorage().nextLoanId;
    }

    function immutableLoanData(uint256 loanId) external view returns (ImmutableLoanData memory) {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        _existingLoan($, loanId);
        return $.immutableLoanData[loanId];
    }

    function mutableLoanData(uint256 loanId) external view returns (MutableLoanData memory) {
        return _existingLoan(_getLoanRegistryStorage(), loanId);
    }

    function cumulativeRepaymentData(uint256 loanId) external view returns (RepaymentData memory) {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        _existingLoan($, loanId);
        return $.cumulativeRepaymentData[loanId];
    }

    function repaymentData(uint256 loanId, uint256 repaymentId) external view returns (RepaymentData memory) {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        _existingRepayment($, loanId, repaymentId);
        return $.repaymentData[loanId][repaymentId];
    }

    function isRepaymentReversed(uint256 loanId, uint256 repaymentId) external view returns (bool) {
        return _getLoanRegistryStorage().reversedRepayments[loanId][repaymentId];
    }

    function disbursements(uint256 loanId) external view returns (Disbursement[] memory) {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        _existingLoan($, loanId);
        return $.disbursements[loanId];
    }

    function economicsEpoch(uint256 loanId, uint256 epochId) external view returns (EconomicsEpoch memory) {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        _existingLoan($, loanId);
        return $.economicsEpochs[loanId][epochId];
    }

    function status(uint256 loanId) external view returns (LoanStatus) {
        return _existingLoan(_getLoanRegistryStorage(), loanId).status;
    }

    function outstanding(uint256 loanId) external view returns (uint256) {
        return _outstanding(_existingLoan(_getLoanRegistryStorage(), loanId));
    }

    function accruedInterest(uint256 loanId) external view returns (uint256) {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        _existingLoan($, loanId);
        return _accruedInterest($, loanId);
    }

    function loanMoney(uint256 loanId) external view returns (LoanMoney memory) {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        MutableLoanData storage loan = _existingLoan($, loanId);
        return LoanMoney({
            disbursed: loan.disbursed,
            repaid: loan.repaid,
            writtenDown: loan.writtenDown,
            outstanding: _outstanding(loan),
            accruedInterest: _accruedInterest($, loanId),
            carvedOut: loan.carvedOut
        });
    }

    function outstandingTotal() external view returns (uint256) {
        return _getLoanRegistryStorage().outstandingTotal;
    }

    function unabsorbedTotal() external view returns (uint256) {
        return _getLoanRegistryStorage().unabsorbedTotal;
    }

    function capitalWallet() external view returns (address) {
        return _getLoanRegistryStorage().capitalWallet;
    }

    function stakedPlUsd() external view returns (address) {
        return address(_getLoanRegistryStorage().stakedPlUsd);
    }

    function pocket() external view returns (address) {
        return address(_getLoanRegistryStorage().pocket);
    }

    function maxFeeBps() external view returns (uint32) {
        return _getLoanRegistryStorage().maxFeeBps;
    }

    function maxResidual() external view returns (uint256) {
        return _getLoanRegistryStorage().maxResidual;
    }

    function _drawLoan(string calldata metadataURI, ImmutableLoanData calldata economics)
        internal
        whenNotPaused
        returns (uint256 loanId)
    {
        if (economics.originalSeniorTranche + economics.originalEquityTranche != economics.originalFacilitySize) {
            revert LoanRegistryInvalidTranches();
        }
        if (economics.originalMaturityDate <= economics.originationDate) revert LoanRegistryInvalidMaturityDate();
        if (economics.originalOfftakerPrice < economics.originalFacilitySize) {
            revert LoanRegistryInvalidOfftakerPrice();
        }

        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        address _capitalWallet = $.capitalWallet;
        if (_capitalWallet == address(0)) revert LoanRegistryNotConfigured();

        loanId = $.nextLoanId;

        $.immutableLoanData[loanId] = economics;

        MutableLoanData storage loan = $.mutableLoanData[loanId];
        loan.currentMaturityTimestamp = economics.originalMaturityDate;
        loan.currentRate = economics.seniorInterestRate;
        loan.metadataURI = metadataURI;

        _mint(_capitalWallet, loanId);

        unchecked {
            ++$.nextLoanId;
        }

        emit LoanDrawn(loanId, metadataURI);
        emit StatusUpdated(loanId, LoanStatus.Approved);
    }

    function _updateMutable(uint256 loanId, LoanStatus newStatus, string calldata metadataURI) internal whenNotPaused {
        MutableLoanData storage loan = _existingLoan(_getLoanRegistryStorage(), loanId);

        LoanStatus currentStatus = loan.status;
        if (currentStatus == LoanStatus.Closed) revert LoanRegistryAlreadyClosed(loanId);

        bool allowed = currentStatus == LoanStatus.Approved || currentStatus == LoanStatus.Default
            ? newStatus == currentStatus
            : newStatus == LoanStatus.Performing || newStatus == LoanStatus.WatchList;
        if (!allowed) revert LoanRegistryWrongCurrentStatus(loanId, currentStatus);

        loan.metadataURI = metadataURI;

        if (newStatus != currentStatus) {
            loan.status = newStatus;
            emit StatusUpdated(loanId, newStatus);
        }
    }

    function _disburse(uint256 loanId, uint256 amount) internal whenNotPaused returns (uint256 index) {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        MutableLoanData storage loan = _existingLoan($, loanId);

        if (amount == 0) revert LoanRegistryInvalidAmount();
        _requireStatusRange(loanId, loan.status, LoanStatus.Approved, LoanStatus.WatchList);
        if (loan.carvedOut) revert LoanRegistryCarvedOut(loanId);

        uint256 disbursed = loan.disbursed + amount;
        uint256 originalSeniorTranche = $.immutableLoanData[loanId].originalSeniorTranche;
        if (disbursed > originalSeniorTranche) {
            revert LoanRegistryDisbursementExceedsTranche(loanId, disbursed, originalSeniorTranche);
        }

        bool isFirst = _advanceEpoch($, loanId);

        loan.disbursed = disbursed;
        if (isFirst) loan.status = LoanStatus.Performing;

        Disbursement[] storage _disbursements = $.disbursements[loanId];
        index = _disbursements.length;
        _disbursements.push(Disbursement({amount: amount, remaining: amount}));

        $.outstandingTotal += amount;

        emit Disbursed(loanId, amount, _outstanding(loan));
        if (isFirst) emit StatusUpdated(loanId, LoanStatus.Performing);
    }

    function _undisburse(uint256 loanId, uint256 index, uint256 amount) internal whenNotPaused {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        MutableLoanData storage loan = _existingLoan($, loanId);

        if (amount == 0) revert LoanRegistryInvalidAmount();
        _requireStatusRange(loanId, loan.status, LoanStatus.Performing, LoanStatus.Default);
        if (loan.carvedOut) revert LoanRegistryCarvedOut(loanId);

        uint256 loanOutstanding = _outstanding(loan);
        if (amount > loanOutstanding) revert LoanRegistryAmountExceedsOutstanding(loanId, amount, loanOutstanding);

        Disbursement[] storage _disbursements = $.disbursements[loanId];
        if (index >= _disbursements.length) revert LoanRegistryNonExistentDisbursement(loanId, index);

        Disbursement storage disbursement = _disbursements[index];
        uint256 remaining = disbursement.remaining;
        if (amount > remaining) revert LoanRegistryAmountExceedsRemaining(loanId, index, amount, remaining);

        _advanceEpoch($, loanId);

        disbursement.remaining = remaining - amount;
        loan.disbursed -= amount;
        $.outstandingTotal -= amount;

        emit Undisbursed(loanId, amount, loanOutstanding - amount);
    }

    function _recordPayment(uint256 loanId, RepaymentData calldata repayment)
        internal
        whenNotPaused
        returns (uint256 repaymentId)
    {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        MutableLoanData storage loan = _existingLoan($, loanId);

        _requireStatusRange(loanId, loan.status, LoanStatus.Performing, LoanStatus.Default);
        _validateRepayment($, loanId, loan, repayment);

        _advanceEpoch($, loanId);

        loan.repaid += repayment.seniorPrincipalRepaid;
        repaymentId = loan.nextRepaymentId;
        unchecked {
            ++loan.nextRepaymentId;
        }
        $.outstandingTotal -= repayment.seniorPrincipalRepaid;

        RepaymentData storage cumulative = $.cumulativeRepaymentData[loanId];
        cumulative.offtakerReceived += repayment.offtakerReceived;
        cumulative.seniorPrincipalRepaid += repayment.seniorPrincipalRepaid;
        cumulative.seniorInterest += repayment.seniorInterest;
        cumulative.equityDistributed += repayment.equityDistributed;
        cumulative.mgmtFee += repayment.mgmtFee;
        cumulative.perfFee += repayment.perfFee;
        cumulative.oetAlloc += repayment.oetAlloc;

        $.repaymentData[loanId][repaymentId] = repayment;

        emit PaymentRecorded(loanId, repaymentId, repayment, _outstanding(loan));
    }

    function _unrecordPayment(uint256 loanId, uint256 repaymentId)
        internal
        whenNotPaused
        returns (RepaymentData memory repayment)
    {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        MutableLoanData storage loan = _existingRepayment($, loanId, repaymentId);

        _requireStatusRange(loanId, loan.status, LoanStatus.Performing, LoanStatus.Default);
        if ($.reversedRepayments[loanId][repaymentId]) {
            revert LoanRegistryRepaymentAlreadyReversed(loanId, repaymentId);
        }

        $.reversedRepayments[loanId][repaymentId] = true;
        repayment = $.repaymentData[loanId][repaymentId];

        _advanceEpoch($, loanId);

        loan.repaid -= repayment.seniorPrincipalRepaid;
        $.outstandingTotal += repayment.seniorPrincipalRepaid;

        RepaymentData storage cumulative = $.cumulativeRepaymentData[loanId];
        cumulative.offtakerReceived -= repayment.offtakerReceived;
        cumulative.seniorPrincipalRepaid -= repayment.seniorPrincipalRepaid;
        cumulative.seniorInterest -= repayment.seniorInterest;
        cumulative.equityDistributed -= repayment.equityDistributed;
        cumulative.mgmtFee -= repayment.mgmtFee;
        cumulative.perfFee -= repayment.perfFee;
        cumulative.oetAlloc -= repayment.oetAlloc;

        emit PaymentUnrecorded(loanId, repaymentId, repayment, _outstanding(loan));
    }

    function _rollover(uint256 loanId, uint32 newRate, uint64 newMaturityTimestamp) internal whenNotPaused {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        MutableLoanData storage loan = _existingLoan($, loanId);

        _requireStatusRange(loanId, loan.status, LoanStatus.Performing, LoanStatus.WatchList);
        if (loan.currentMaturityTimestamp > block.timestamp) revert LoanRegistryNotMatured(loanId);

        _setTerms($, loanId, newRate, newMaturityTimestamp);

        emit LoanRolledOver(loanId, newRate, newMaturityTimestamp);
    }

    function _amendEconomics(uint256 loanId, uint32 newRate, uint64 newMaturityTimestamp) internal whenNotPaused {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        MutableLoanData storage loan = _existingLoan($, loanId);

        if (loan.status == LoanStatus.Closed) revert LoanRegistryAlreadyClosed(loanId);

        _setTerms($, loanId, newRate, newMaturityTimestamp);

        emit EconomicsAmended(loanId, newRate, newMaturityTimestamp);
    }

    function _setDefault(uint256 loanId) internal whenNotPaused {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        MutableLoanData storage loan = _existingLoan($, loanId);

        _requireStatusRange(loanId, loan.status, LoanStatus.Performing, LoanStatus.WatchList);

        uint256 loanOutstanding = _outstanding(loan);
        bool firstDefault = !loan.carvedOut;

        loan.status = LoanStatus.Default;
        loan.carvedOut = true;

        uint256 moved = firstDefault ? _carveOut($, loanId, loanOutstanding) : 0;

        emit StatusUpdated(loanId, LoanStatus.Default);
        emit LoanDefaulted(loanId, loanOutstanding, moved);
    }

    function _writeDown(uint256 loanId, uint256 amount) internal whenNotPaused {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        MutableLoanData storage loan = _existingLoan($, loanId);

        if (loan.status != LoanStatus.Default) revert LoanRegistryWrongCurrentStatus(loanId, loan.status);
        if (amount == 0) revert LoanRegistryInvalidAmount();

        uint256 loanOutstanding = _outstanding(loan);
        if (amount > loanOutstanding) revert LoanRegistryAmountExceedsOutstanding(loanId, amount, loanOutstanding);

        _advanceEpoch($, loanId);

        loan.writtenDown += amount;
        $.outstandingTotal -= amount;

        uint256 burned = _pocketBurn($, loanId, amount);
        uint256 unabsorbed = amount - burned;
        $.unabsorbedTotal += unabsorbed;

        emit LoanWrittenDown(loanId, amount, loanOutstanding - amount, burned, unabsorbed);
    }

    function _adjustInterest(uint256 loanId, int256 delta, bytes32 reasonHash) internal whenNotPaused {
        MutableLoanData storage loan = _existingLoan(_getLoanRegistryStorage(), loanId);

        _requireStatusRange(loanId, loan.status, LoanStatus.Performing, LoanStatus.Default);

        loan.interestAdjustment += delta;

        emit InterestAdjusted(loanId, delta, reasonHash);
    }

    function _cure(uint256 loanId) internal whenNotPaused {
        MutableLoanData storage loan = _existingLoan(_getLoanRegistryStorage(), loanId);

        if (loan.status != LoanStatus.Default) revert LoanRegistryWrongCurrentStatus(loanId, loan.status);

        loan.status = LoanStatus.WatchList;

        emit StatusUpdated(loanId, LoanStatus.WatchList);
    }

    function _closeLoan(uint256 loanId, ClosureReason reason) internal whenNotPaused {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        MutableLoanData storage loan = _existingLoan($, loanId);

        _requireStatusRange(loanId, loan.status, LoanStatus.Approved, LoanStatus.WatchList);

        if (reason == ClosureReason.Cancelled) {
            if (loan.disbursed != 0) revert LoanRegistryOutstandingNotZero(loanId);
        } else if (reason == ClosureReason.ScheduledMaturity || reason == ClosureReason.EarlyRepayment) {
            if (_outstanding(loan) != 0) revert LoanRegistryOutstandingNotZero(loanId);
        } else {
            revert LoanRegistryInvalidClosureReason(reason);
        }

        uint256 waived = _accruedInterest($, loanId);
        uint256 _maxResidual = $.maxResidual;
        if (waived > _maxResidual) revert LoanRegistryResidualExceedsMax(loanId, waived, _maxResidual);

        _close($, loanId, reason, waived);
    }

    function _closeDefaulted(uint256 loanId, ClosureReason reason) internal whenNotPaused {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        MutableLoanData storage loan = _existingLoan($, loanId);

        if (loan.status != LoanStatus.Default) revert LoanRegistryWrongCurrentStatus(loanId, loan.status);
        if (reason != ClosureReason.Default && reason != ClosureReason.OtherWriteDown) {
            revert LoanRegistryInvalidClosureReason(reason);
        }
        if (_outstanding(loan) != 0) revert LoanRegistryOutstandingNotZero(loanId);

        _close($, loanId, reason, _accruedInterest($, loanId));
    }

    function _setCapitalWallet(address newCapitalWallet) internal {
        if (newCapitalWallet == address(0)) revert LoanRegistryZeroAddress();

        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        if ($.capitalWallet == newCapitalWallet) revert LoanRegistrySameValue();
        $.capitalWallet = newCapitalWallet;

        emit CapitalWalletSet(newCapitalWallet);
    }

    function _setStakedPlUsd(address newStakedPlUsd) internal {
        if (newStakedPlUsd == address(0)) revert LoanRegistryZeroAddress();

        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        if (address($.stakedPlUsd) == newStakedPlUsd) revert LoanRegistrySameValue();
        $.stakedPlUsd = IStakedPipelineUSD(newStakedPlUsd);

        emit StakedPlUsdSet(newStakedPlUsd);
    }

    function _setPocket(address newPocket) internal {
        if (newPocket == address(0)) revert LoanRegistryZeroAddress();

        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        if (address($.pocket) == newPocket) revert LoanRegistrySameValue();
        $.pocket = IPocket(newPocket);

        emit PocketSet(newPocket);
    }

    function _setMaxFeeBps(uint32 newMaxFeeBps) internal {
        if (newMaxFeeBps > BPS_ONE) revert LoanRegistryInvalidMaxFeeBps();

        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        if ($.maxFeeBps == newMaxFeeBps) revert LoanRegistrySameValue();
        $.maxFeeBps = newMaxFeeBps;

        emit MaxFeeBpsSet(newMaxFeeBps);
    }

    function _setMaxResidual(uint256 newMaxResidual) internal {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        if ($.maxResidual == newMaxResidual) revert LoanRegistrySameValue();
        $.maxResidual = newMaxResidual;

        emit MaxResidualSet(newMaxResidual);
    }

    function _close(LoanRegistryStorage storage $, uint256 loanId, ClosureReason reason, uint256 waived) private {
        uint256 paid = $.cumulativeRepaymentData[loanId].seniorInterest;

        MutableLoanData storage loan = $.mutableLoanData[loanId];
        loan.status = LoanStatus.Closed;
        loan.closureReason = reason;

        emit StatusUpdated(loanId, LoanStatus.Closed);
        emit InterestSettled(loanId, paid + waived, paid, waived);
        emit LoanClosed(loanId, reason);
    }

    function _carveOut(LoanRegistryStorage storage $, uint256 loanId, uint256 amount) private returns (uint256 moved) {
        IStakedPipelineUSD _stakedPlUsd = $.stakedPlUsd;
        if (address(_stakedPlUsd) == address(0)) revert LoanRegistryNotConfigured();

        moved = _stakedPlUsd.carveOut(loanId, amount);
        if (moved > amount) revert LoanRegistryCounterpartOverreported(amount, moved);
    }

    function _pocketBurn(LoanRegistryStorage storage $, uint256 loanId, uint256 amount)
        private
        returns (uint256 burned)
    {
        IPocket _pocket = $.pocket;
        if (address(_pocket) == address(0)) revert LoanRegistryNotConfigured();

        burned = _pocket.burn(loanId, amount);
        if (burned > amount) revert LoanRegistryCounterpartOverreported(amount, burned);
    }

    function _validateRepayment(
        LoanRegistryStorage storage $,
        uint256 loanId,
        MutableLoanData storage loan,
        RepaymentData calldata repayment
    ) private view {
        uint256 fees = repayment.mgmtFee + repayment.perfFee + repayment.oetAlloc;
        if (
            repayment.seniorPrincipalRepaid + repayment.seniorInterest + repayment.equityDistributed + fees
                != repayment.offtakerReceived
        ) {
            revert LoanRegistryWrongRepaymentData();
        }

        if (loan.status == LoanStatus.Default && (fees != 0 || repayment.equityDistributed != 0)) {
            revert LoanRegistryNonZeroOnDefault(loanId);
        }

        uint256 maxSeniorInterest = _accruedInterest($, loanId);
        if (repayment.seniorInterest > maxSeniorInterest) {
            revert LoanRegistryInterestExceedsMax(loanId, repayment.seniorInterest, maxSeniorInterest);
        }

        uint256 feeCap =
            Math.mulDiv(repayment.seniorInterest + repayment.mgmtFee + repayment.perfFee, $.maxFeeBps, BPS_ONE);
        if (fees > feeCap) revert LoanRegistryFeesExceedCap(loanId, fees, feeCap);

        uint256 repaidAndWrittenDown = loan.repaid + repayment.seniorPrincipalRepaid + loan.writtenDown;
        if (repaidAndWrittenDown > loan.disbursed) {
            revert LoanRegistryRepaidExceedsDisbursed(loanId, repaidAndWrittenDown, loan.disbursed);
        }

        uint256 cumulativeOfftakerReceived =
            $.cumulativeRepaymentData[loanId].offtakerReceived + repayment.offtakerReceived;
        uint256 originalOfftakerPrice = $.immutableLoanData[loanId].originalOfftakerPrice;
        if (cumulativeOfftakerReceived > originalOfftakerPrice) {
            revert LoanRegistryOfftakerExceedsPrice(loanId, cumulativeOfftakerReceived, originalOfftakerPrice);
        }
    }

    function _advanceEpoch(LoanRegistryStorage storage $, uint256 loanId) private returns (bool isFirst) {
        MutableLoanData storage loan = $.mutableLoanData[loanId];

        if (loan.nextEconomicsEpochsId == 0) {
            $.economicsEpochs[loanId][0] = EconomicsEpoch({
                accruedInterest: 0,
                effectiveFrom: uint64(block.timestamp),
                maturityDate: loan.currentMaturityTimestamp,
                seniorInterestRate: loan.currentRate
            });
            loan.nextEconomicsEpochsId = 1;
            return true;
        }

        _appendEconomicsEpoch($, loanId, loan.currentMaturityTimestamp, loan.currentRate);
    }

    function _setTerms(LoanRegistryStorage storage $, uint256 loanId, uint32 newRate, uint64 newMaturityTimestamp)
        private
    {
        MutableLoanData storage loan = $.mutableLoanData[loanId];

        if (loan.nextEconomicsEpochsId != 0) _appendEconomicsEpoch($, loanId, newMaturityTimestamp, newRate);

        loan.currentRate = newRate;
        loan.currentMaturityTimestamp = newMaturityTimestamp;
    }

    function _appendEconomicsEpoch(
        LoanRegistryStorage storage $,
        uint256 loanId,
        uint64 maturityDate,
        uint32 seniorInterestRate
    ) private {
        MutableLoanData storage loan = $.mutableLoanData[loanId];
        uint256 economicsEpochId = loan.nextEconomicsEpochsId;
        EconomicsEpoch storage lastEpoch = $.economicsEpochs[loanId][economicsEpochId - 1];

        $.economicsEpochs[loanId][economicsEpochId] = EconomicsEpoch({
            accruedInterest: lastEpoch.accruedInterest + _epochInterest(lastEpoch, _outstanding(loan)),
            effectiveFrom: uint64(block.timestamp),
            maturityDate: maturityDate,
            seniorInterestRate: seniorInterestRate
        });

        unchecked {
            loan.nextEconomicsEpochsId = economicsEpochId + 1;
        }
    }

    function _accruedInterest(LoanRegistryStorage storage $, uint256 loanId) private view returns (uint256) {
        MutableLoanData storage loan = $.mutableLoanData[loanId];

        uint256 economicsEpochsCount = loan.nextEconomicsEpochsId;
        if (economicsEpochsCount == 0 || loan.status == LoanStatus.Closed) return 0;

        EconomicsEpoch storage lastEpoch = $.economicsEpochs[loanId][economicsEpochsCount - 1];
        uint256 gross = lastEpoch.accruedInterest + _epochInterest(lastEpoch, _outstanding(loan));

        RepaymentData storage cumulative = $.cumulativeRepaymentData[loanId];
        uint256 recorded = cumulative.seniorInterest + cumulative.mgmtFee + cumulative.perfFee;

        int256 net = gross.toInt256() - recorded.toInt256() + loan.interestAdjustment;
        return net > 0 ? net.toUint256() : 0;
    }

    function _epochInterest(EconomicsEpoch storage epoch, uint256 principal) private view returns (uint256) {
        return Math.mulDiv((block.timestamp - epoch.effectiveFrom) * epoch.seniorInterestRate, principal, YEAR * ONE);
    }

    function _outstanding(MutableLoanData storage loan) private view returns (uint256) {
        return loan.disbursed - loan.repaid - loan.writtenDown;
    }

    function _existingLoan(LoanRegistryStorage storage $, uint256 loanId)
        private
        view
        returns (MutableLoanData storage)
    {
        if (loanId >= $.nextLoanId) revert LoanRegistryNonExistentLoanId(loanId);
        return $.mutableLoanData[loanId];
    }

    function _existingRepayment(LoanRegistryStorage storage $, uint256 loanId, uint256 repaymentId)
        private
        view
        returns (MutableLoanData storage loan)
    {
        loan = _existingLoan($, loanId);
        if (repaymentId >= loan.nextRepaymentId) revert LoanRegistryNonExistentRepayment(loanId, repaymentId);
    }

    function _requireStatusRange(uint256 loanId, LoanStatus currentStatus, LoanStatus min, LoanStatus max)
        private
        pure
    {
        if (currentStatus < min || currentStatus > max) {
            revert LoanRegistryWrongCurrentStatus(loanId, currentStatus);
        }
    }

    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address from) {
        from = super._update(to, tokenId, auth);
        if (from != address(0)) revert LoanRegistryNonTransferrable();
    }
}
