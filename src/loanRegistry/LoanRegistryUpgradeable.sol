// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    ERC721PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";

import {ILoanRegistry} from "../interfaces/ILoanRegistry.sol";

contract LoanRegistryUpgradeable is ERC721PausableUpgradeable, ILoanRegistry {
    event LoanMinted(
        uint256 indexed loanId,
        address indexed holder,
        string indexed metadataURI,
        uint64 initialMaturity,
        string location
    );
    event StatusUpdated(uint256 indexed loanId, LoanStatus indexed newStatus);
    event CCRUpdated(uint256 indexed loanId, uint32 newCcrBps);
    event LocationUpdated(uint256 indexed loanId, string indexed newLocation);
    event LoanDefaulted(uint256 indexed loanId, uint32 ccrBps);
    event LoanClosed(uint256 indexed loanId, ClosureReason indexed reason);
    event Repayment(
        uint256 indexed tokenId,
        uint256 offtakerAmount,
        uint256 seniorPrincipal,
        uint256 seniorInterest,
        uint256 equityAmount
    );

    error LoanRegistryNonExistentLoanId(uint256);
    error LoanRegistryAlreadyClosed(uint256);
    error LoanRegistryWrongCurrentStatus(uint256 loanId, LoanStatus currentStatus);
    error LoanRegistrySameStatus(uint256 loanId);
    error LoanRegistryInapplicableStatus(uint256 loanId, LoanStatus status);
    error LoanRegistryNonTransferrable();
    error LoanRegistryWrongRepaymentData();

    /// @custom:storage-location erc7201:pipeline.storage.LoanRegistry
    struct LoanRegistryStorage {
        uint256 nextLoanId;
        uint256 offtakerReceivedTotal;
        uint256 seniorPrincipalRepaid;
        uint256 seniorInterestRepaid;
        uint256 equityDistributed;
        mapping(uint256 index => string) metadataURI;
        mapping(uint256 index => MutableLoanData) mutableLoanData;
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
        return _getLoanRegistryStorage().metadataURI[tokenId];
    }

    function mutableLoanData(uint256 loanId) external view returns (MutableLoanData memory) {
        return _getLoanRegistryStorage().mutableLoanData[loanId];
    }

    function nextLoanId() external view returns (uint256) {
        return _getLoanRegistryStorage().nextLoanId;
    }

    function repaymentData()
        external
        view
        returns (
            uint256 offtakerReceivedTotal,
            uint256 seniorPrincipalRepaid,
            uint256 seniorInterestRepaid,
            uint256 equityDistributed
        )
    {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();

        offtakerReceivedTotal = $.offtakerReceivedTotal;
        seniorPrincipalRepaid = $.seniorPrincipalRepaid;
        seniorInterestRepaid = $.seniorInterestRepaid;
        equityDistributed = $.equityDistributed;
    }

    function _mintLoan(address to, string calldata metadataURI, uint64 initialMaturity, string calldata location)
        internal
        whenNotPaused
        returns (uint256 loanId)
    {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        loanId = $.nextLoanId;

        $.metadataURI[loanId] = metadataURI;
        $.mutableLoanData[loanId].maturity = initialMaturity;
        $.mutableLoanData[loanId].location = location;

        _mint(to, loanId);

        unchecked {
            ++$.nextLoanId;
        }

        emit LoanMinted(loanId, to, metadataURI, initialMaturity, location);
    }

    function _updateStatus(uint256 loanId, LoanStatus status) internal whenNotPaused {
        if (status > LoanStatus.WatchList) revert LoanRegistryInapplicableStatus(loanId, status);

        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        if (loanId >= $.nextLoanId) revert LoanRegistryNonExistentLoanId(loanId);

        LoanStatus currentStatus = $.mutableLoanData[loanId].status;
        if (currentStatus > LoanStatus.WatchList) revert LoanRegistryWrongCurrentStatus(loanId, currentStatus);
        if (currentStatus == status) revert LoanRegistrySameStatus(loanId);

        $.mutableLoanData[loanId].status = status;

        emit StatusUpdated(loanId, status);
    }

    function _updateCCR(uint256 loanId, uint32 newCcrBps) internal whenNotPaused {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        if (loanId >= $.nextLoanId) revert LoanRegistryNonExistentLoanId(loanId);

        LoanStatus currentStatus = $.mutableLoanData[loanId].status;
        if (currentStatus > LoanStatus.WatchList) revert LoanRegistryWrongCurrentStatus(loanId, currentStatus);

        $.mutableLoanData[loanId].ccrBps = newCcrBps;

        emit CCRUpdated(loanId, newCcrBps);
    }

    function _updateLocation(uint256 loanId, string calldata newLocation) internal whenNotPaused {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        if (loanId >= $.nextLoanId) revert LoanRegistryNonExistentLoanId(loanId);

        LoanStatus currentStatus = $.mutableLoanData[loanId].status;
        if (currentStatus > LoanStatus.WatchList) revert LoanRegistryWrongCurrentStatus(loanId, currentStatus);

        $.mutableLoanData[loanId].location = newLocation;

        emit LocationUpdated(loanId, newLocation);
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

    function _recordPayment(
        uint256 loanId,
        uint256 offtakerAmount,
        uint256 seniorPrincipal,
        uint256 seniorInterest,
        uint256 equityAmount
    ) internal whenNotPaused {
        if (seniorPrincipal + seniorInterest + equityAmount > offtakerAmount) {
            revert LoanRegistryWrongRepaymentData();
        }

        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        if (loanId >= $.nextLoanId) revert LoanRegistryNonExistentLoanId(loanId);

        $.offtakerReceivedTotal += offtakerAmount;
        $.seniorPrincipalRepaid += seniorPrincipal;
        $.seniorInterestRepaid += seniorInterest;
        $.equityDistributed += equityAmount;

        emit Repayment(loanId, offtakerAmount, seniorPrincipal, seniorInterest, equityAmount);
    }

    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address from) {
        from = super._update(to, tokenId, auth);
        if (from != address(0)) revert LoanRegistryNonTransferrable();
    }
}
