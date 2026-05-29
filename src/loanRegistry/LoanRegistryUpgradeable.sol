// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    ERC721PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ILoanRegistry} from "../interfaces/ILoanRegistry.sol";

abstract contract LoanRegistryUpgradeable is ERC721PausableUpgradeable, ILoanRegistry {
    using Math for uint256;

    uint256 public constant ONE = 1_000_000;
    uint256 constant YEAR = 31557600;

    event LoanDrawn(uint256 indexed loanId, address indexed holder, string indexed metadataURI);
    event StatusUpdated(uint256 indexed loanId, LoanStatus indexed newStatus);
    event CCRUpdated(uint256 indexed loanId, uint32 newCcrBps);
    event LocationUpdated(uint256 indexed loanId, string indexed newLocation);
    event LoanDefaulted(uint256 indexed loanId, uint32 ccrBps);
    event LoanClosed(uint256 indexed loanId, ClosureReason indexed reason);
    event PaymentRecorded(uint256 indexed tokenId, uint256 indexed repaymentId, RepaymentData repaymentData);

    error LoanRegistryNonExistentLoanId(uint256);
    error LoanRegistryAlreadyClosed(uint256);
    error LoanRegistryWrongCurrentStatus(uint256 loanId, LoanStatus currentStatus);
    error LoanRegistrySameStatus(uint256 loanId);
    error LoanRegistryInapplicableStatus(uint256 loanId, LoanStatus status);
    error LoanRegistryNonTransferrable();
    error LoanRegistryWrongRepaymentData();
    error LoanRegistryLowCcr();
    error LoanRegistryAlreadyMinted(uint256 loanId, uint256 repaymentId);
    error LoanRegistryNonExistentRepayment(uint256 loanId, uint256 repaymentId);

    /// @custom:storage-location erc7201:pipeline.storage.LoanRegistry
    struct LoanRegistryStorage {
        uint256 nextLoanId;
        mapping(uint256 loanId => ImmutableLoanData) immutableLoanData;
        mapping(uint256 loanId => MutableLoanData) mutableLoanData;
        mapping(uint256 loanId => RepaymentData) cumulativeRepaymentData;
        mapping(uint256 loanId => mapping(uint256 repaymentId => RepaymentData)) repaymentData;
        mapping(uint256 loanId => mapping(uint256 repaymentId => bool)) minted;
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
        return _getLoanRegistryStorage().mutableLoanData[tokenId].metadataURI;
    }

    function nextLoanId() external view returns (uint256) {
        return _getLoanRegistryStorage().nextLoanId;
    }

    function immutableLoanData(uint256 loanId) external view returns (ImmutableLoanData memory) {
        return _getLoanRegistryStorage().immutableLoanData[loanId];
    }

    function mutableLoanData(uint256 loanId) external view returns (MutableLoanData memory) {
        return _getLoanRegistryStorage().mutableLoanData[loanId];
    }

    function cumulativeRepaymentData(uint256 loanId) external view returns (RepaymentData memory) {
        return _getLoanRegistryStorage().cumulativeRepaymentData[loanId];
    }

    function repaymentData(uint256 loanId, uint256 repaymentId) external view returns (RepaymentData memory) {
        return _getLoanRegistryStorage().repaymentData[loanId][repaymentId];
    }

    function canYieldBeMinted(uint256 loanId, uint256 repaymentId) external view returns (bool) {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        if (loanId >= $.nextLoanId) return false;
        if (repaymentId >= $.mutableLoanData[loanId].nextRepaymentId) return false;
        return !$.minted[loanId][repaymentId];
    }

    function _drawLoan(
        address originator,
        string calldata metadataURI,
        ImmutableLoanData calldata economics,
        uint32 initialCcrBps,
        LocationUpdate calldata initialLocation
    ) internal whenNotPaused returns (uint256 loanId) {
        if (initialCcrBps < ONE) revert LoanRegistryLowCcr();
        if (economics.originalSeniorTranche + economics.originalEquityTranche != economics.originalFacilitySize) {
            revert();
        }
        if (economics.originalMaturityDate <= economics.originationDate) revert();
        if (economics.originalOfftakerPrice < economics.originalFacilitySize) revert();

        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        loanId = $.nextLoanId;

        $.immutableLoanData[loanId] = economics;

        MutableLoanData storage _mutableLoanData = $.mutableLoanData[loanId];

        _mutableLoanData.metadataURI = metadataURI;
        _mutableLoanData.currentMaturityTimestamp = economics.originalMaturityDate;
        _mutableLoanData.ccrBps = initialCcrBps;
        _mutableLoanData.lastReportedCCRTimestamp = uint64(block.timestamp);
        _mutableLoanData.currentLocation = initialLocation;
        _mutableLoanData.nextEconomicsEpochsId = 1;

        $.economicsEpochs[loanId][0] = EconomicsEpoch({
            accruedInterest: 0,
            effectiveFrom: economics.originationDate,
            maturityDate: economics.originalMaturityDate,
            seniorInterestRateBps: economics.seniorInterestRateBps
        });

        _mint(originator, loanId);

        unchecked {
            ++$.nextLoanId;
        }

        emit LoanDrawn(loanId, originator, metadataURI);
    }

    function _updateMutable(
        uint256 loanId,
        string calldata metadataURI,
        LoanStatus status,
        uint32 newCCR,
        LocationUpdate calldata newLocation
    ) internal whenNotPaused {
        if (status >= LoanStatus.Default) revert();

        LoanRegistryStorage storage $ = _getLoanRegistryStorage();

        MutableLoanData storage _mutableLoanData = $.mutableLoanData[loanId];

        _mutableLoanData.metadataURI = metadataURI;
        _mutableLoanData.status = status;
        _mutableLoanData.ccrBps = newCCR;
        _mutableLoanData.lastReportedCCRTimestamp = uint64(block.timestamp);
        _mutableLoanData.currentLocation = newLocation;
    }

    function _recordPayment(uint256 loanId, RepaymentData calldata repaymentUpdate)
        internal
        whenNotPaused
        returns (uint256 repaymentId)
    {
        uint256 repaymentSum = repaymentUpdate.seniorPrincipalRepaid + repaymentUpdate.seniorInterest
            + repaymentUpdate.equityDistributed + repaymentUpdate.mgmtFee + repaymentUpdate.perfFee
            + repaymentUpdate.oetAlloc;
        if (repaymentSum > repaymentUpdate.offtakerReceived) {
            revert LoanRegistryWrongRepaymentData();
        }

        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        if (loanId >= $.nextLoanId) revert LoanRegistryNonExistentLoanId(loanId);

        MutableLoanData storage _mutableLoanData = $.mutableLoanData[loanId];
        if (_mutableLoanData.status <= LoanStatus.WatchList) {
            revert LoanRegistryWrongCurrentStatus(loanId, $.mutableLoanData[loanId].status);
        }

        if (repaymentUpdate.seniorInterest > _calculateMaxInterest(loanId)) revert();

        RepaymentData storage _repaymentData = $.cumulativeRepaymentData[loanId];

        _repaymentData.offtakerReceived += repaymentUpdate.offtakerReceived;
        _repaymentData.equityDistributed += repaymentUpdate.equityDistributed;
        _repaymentData.seniorPrincipalRepaid += repaymentUpdate.seniorPrincipalRepaid;
        _repaymentData.seniorInterest += repaymentUpdate.seniorInterest;
        _repaymentData.mgmtFee += repaymentUpdate.mgmtFee;
        _repaymentData.perfFee += repaymentUpdate.perfFee;
        _repaymentData.oetAlloc += repaymentUpdate.oetAlloc;

        repaymentId = $.mutableLoanData[loanId].nextRepaymentId;
        $.repaymentData[loanId][repaymentId] = repaymentUpdate;

        unchecked {
            ++$.mutableLoanData[loanId].nextRepaymentId;
        }

        ImmutableLoanData storage _immutableLoanData = $.immutableLoanData[loanId];
        RepaymentData storage _cumulativeRepaymentData = $.cumulativeRepaymentData[loanId];
        uint256 interestMultiplier = _lastEpochInterestMultiplier(loanId);
        uint256 lastEpochInterest = interestMultiplier
            * (_immutableLoanData.originalSeniorTranche - _cumulativeRepaymentData.seniorPrincipalRepaid);

        uint256 economicsEpochId = _mutableLoanData.nextEconomicsEpochsId;
        $.economicsEpochs[loanId][economicsEpochId] = EconomicsEpoch({
            accruedInterest: $.economicsEpochs[loanId][economicsEpochId - 1].accruedInterest + lastEpochInterest,
            effectiveFrom: uint64(block.timestamp),
            maturityDate: $.economicsEpochs[loanId][economicsEpochId - 1].maturityDate,
            seniorInterestRateBps: $.economicsEpochs[loanId][economicsEpochId - 1].seniorInterestRateBps
        });

        unchecked {
            ++_mutableLoanData.nextEconomicsEpochsId;
        }

        emit PaymentRecorded(loanId, repaymentId, repaymentUpdate);
    }

    function _rollover(uint256 loanId, uint32 newRateBps, uint64 newMaturityTimestamp) internal {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        if (loanId >= $.nextLoanId) revert LoanRegistryNonExistentLoanId(loanId);

        MutableLoanData storage _mutableLoanData = $.mutableLoanData[loanId];
        if (_mutableLoanData.status >= LoanStatus.Default) revert();
        if (_mutableLoanData.currentMaturityTimestamp > block.timestamp) revert();

        _mutableLoanData.currentMaturityTimestamp = newMaturityTimestamp;
        _mutableLoanData.status = LoanStatus.Performing;

        ImmutableLoanData storage _immutableLoanData = $.immutableLoanData[loanId];
        RepaymentData storage _cumulativeRepaymentData = $.cumulativeRepaymentData[loanId];
        uint256 interestMultiplier = _lastEpochInterestMultiplier(loanId);
        uint256 lastEpochInterest = interestMultiplier
            * (_immutableLoanData.originalSeniorTranche - _cumulativeRepaymentData.seniorPrincipalRepaid);

        uint256 economicsEpochId = _mutableLoanData.nextEconomicsEpochsId;
        $.economicsEpochs[loanId][economicsEpochId] = EconomicsEpoch({
            accruedInterest: $.economicsEpochs[loanId][economicsEpochId - 1].accruedInterest + lastEpochInterest,
            effectiveFrom: uint64(block.timestamp),
            maturityDate: newMaturityTimestamp,
            seniorInterestRateBps: newRateBps
        });

        unchecked {
            ++_mutableLoanData.nextEconomicsEpochsId;
        }
    }

    function _amendEconomics(uint256 loanId, uint32 newRateBps, uint64 newMaturityTimestamp) internal {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        if (loanId >= $.nextLoanId) revert LoanRegistryNonExistentLoanId(loanId);

        MutableLoanData storage _mutableLoanData = $.mutableLoanData[loanId];

        _mutableLoanData.currentMaturityTimestamp = newMaturityTimestamp;
        _mutableLoanData.status = LoanStatus.Performing;

        ImmutableLoanData storage _immutableLoanData = $.immutableLoanData[loanId];
        RepaymentData storage _cumulativeRepaymentData = $.cumulativeRepaymentData[loanId];
        uint256 interestMultiplier = _lastEpochInterestMultiplier(loanId);
        uint256 lastEpochInterest = interestMultiplier
            * (_immutableLoanData.originalSeniorTranche - _cumulativeRepaymentData.seniorPrincipalRepaid);

        uint256 economicsEpochId = _mutableLoanData.nextEconomicsEpochsId;
        $.economicsEpochs[loanId][economicsEpochId] = EconomicsEpoch({
            accruedInterest: $.economicsEpochs[loanId][economicsEpochId - 1].accruedInterest + lastEpochInterest,
            effectiveFrom: uint64(block.timestamp),
            maturityDate: newMaturityTimestamp,
            seniorInterestRateBps: newRateBps
        });

        unchecked {
            ++_mutableLoanData.nextEconomicsEpochsId;
        }
    }

    function _setDefault(uint256 loanId, uint32 ccrBps) internal whenNotPaused {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        if (loanId >= $.nextLoanId) revert LoanRegistryNonExistentLoanId(loanId);

        LoanStatus currentStatus = $.mutableLoanData[loanId].status;
        if (currentStatus > LoanStatus.WatchList) revert LoanRegistryWrongCurrentStatus(loanId, currentStatus);

        MutableLoanData storage loanData = $.mutableLoanData[loanId];
        loanData.status = LoanStatus.Default;
        loanData.ccrBps = ccrBps;

        emit LoanDefaulted(loanId, ccrBps);
    }

    function _closeLoan(uint256 loanId, ClosureReason reason) internal whenNotPaused {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        if (loanId >= $.nextLoanId) revert LoanRegistryNonExistentLoanId(loanId);

        LoanStatus currentStatus = $.mutableLoanData[loanId].status;
        if (currentStatus == LoanStatus.Closed) revert LoanRegistryAlreadyClosed(loanId);
        if (currentStatus == LoanStatus.Default && reason != ClosureReason.Default) {
            revert LoanRegistryWrongCurrentStatus(loanId, currentStatus);
        }

        $.mutableLoanData[loanId].status = LoanStatus.Closed;
        $.mutableLoanData[loanId].closureReason = reason;

        emit LoanClosed(loanId, reason);
    }

    function _markMinted(uint256 loanId, uint256 repaymentId) internal whenNotPaused {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        if (loanId >= $.nextLoanId) revert LoanRegistryNonExistentLoanId(loanId);
        if (repaymentId >= $.mutableLoanData[loanId].nextRepaymentId) {
            revert LoanRegistryNonExistentRepayment(loanId, repaymentId);
        }

        if ($.minted[loanId][repaymentId]) revert LoanRegistryAlreadyMinted(loanId, repaymentId);

        $.minted[loanId][repaymentId] = true;
    }

    function _calculateMaxInterest(uint256 loanId) private view returns (uint256) {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();

        ImmutableLoanData storage _immutableLoanData = $.immutableLoanData[loanId];
        MutableLoanData storage _mutableLoanData = $.mutableLoanData[loanId];
        RepaymentData storage _cumulativeRepaymentData = $.cumulativeRepaymentData[loanId];

        uint256 economicsEpochId = _mutableLoanData.nextEconomicsEpochsId - 1;
        EconomicsEpoch storage economicsEpoch = $.economicsEpochs[loanId][economicsEpochId];

        uint256 lastEpochInterestMultiplier =
            (ONE + (block.timestamp - economicsEpoch.effectiveFrom).mulDiv(economicsEpoch.seniorInterestRateBps, YEAR));

        uint256 lastEpochInterest = lastEpochInterestMultiplier
            * (_immutableLoanData.originalSeniorTranche - _cumulativeRepaymentData.seniorPrincipalRepaid);
        return economicsEpoch.accruedInterest + lastEpochInterest - _cumulativeRepaymentData.seniorPrincipalRepaid;
    }

    function _lastEpochInterestMultiplier(uint256 loanId) private view returns (uint256) {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();

        MutableLoanData storage _mutableLoanData = $.mutableLoanData[loanId];
        uint256 economicsEpochId = _mutableLoanData.nextEconomicsEpochsId - 1;
        EconomicsEpoch storage economicsEpoch = $.economicsEpochs[loanId][economicsEpochId];

        return
            (ONE + (block.timestamp - economicsEpoch.effectiveFrom).mulDiv(economicsEpoch.seniorInterestRateBps, YEAR));
    }

    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address from) {
        from = super._update(to, tokenId, auth);
        if (from != address(0)) revert LoanRegistryNonTransferrable();
    }
}
