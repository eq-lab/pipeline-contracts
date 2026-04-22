// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {
    ERC721PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";

import {ILoanRegistry} from "../interfaces/ILoanRegistry.sol";

contract LoanRegistryUpgradeable is ERC721PausableUpgradeable, ILoanRegistry {
    event StatusUpdated(uint256 indexed loanId, LoanStatus indexed newStatus);
    event CCRUpdated(uint256 indexed loanId, uint256 newCcrBps);
    event LocationUpdated(uint256 indexed loanId, bytes32 indexed newLocation);
    event LoanDefaulted(uint256 indexed loanId);
    event LoanClosed(uint256 indexed loanId, ClosureReason indexed reason);

    error LoanRegistryNonExistentLoanId(uint256);
    error LoanRegistryAlreadyClosed(uint256);
    error LoanRegistryWrongCurrentStatus(uint256 loanId, LoanStatus currentStatus);
    error LoanRegistrySameStatus(uint256 loanId);
    error LoanRegistryInapplicableStatus(uint256 loanId, LoanStatus status);
    error LoanRegistryNonTransferrable();

    /// @custom:storage-location erc7201:pipeline.storage.LoanRegistry
    struct LoanRegistryStorage {
        uint256 nextLoanId;
        mapping(uint256 index => ImmutableLoanData) immutableLoanData;
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

    function immutableLoanData(uint256 loanId) external view returns (ImmutableLoanData memory) {
        return _getLoanRegistryStorage().immutableLoanData[loanId];
    }

    function mutableLoanData(uint256 loanId) external view returns (MutableLoanData memory) {
        return _getLoanRegistryStorage().mutableLoanData[loanId];
    }

    function nextLoanId() external view returns (uint256) {
        return _getLoanRegistryStorage().nextLoanId;
    }

    function _mintLoan(address to, ImmutableLoanData calldata data, uint64 initialMaturity, bytes32 location)
        internal
        returns (uint256 loanId)
    {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        loanId = $.nextLoanId;

        $.immutableLoanData[loanId] = data;
        $.mutableLoanData[loanId].maturity = initialMaturity;
        $.mutableLoanData[loanId].location = location;

        _mint(to, loanId);

        unchecked {
            ++$.nextLoanId;
        }
    }

    function _updateStatus(uint256 loanId, LoanStatus status) internal {
        if (status > LoanStatus.WatchList) revert LoanRegistryInapplicableStatus(loanId, status);

        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        if (loanId >= $.nextLoanId) revert LoanRegistryNonExistentLoanId(loanId);

        LoanStatus currentStatus = $.mutableLoanData[loanId].status;
        if (currentStatus > LoanStatus.WatchList) revert LoanRegistryWrongCurrentStatus(loanId, currentStatus);
        if (currentStatus == status) revert LoanRegistrySameStatus(loanId);

        $.mutableLoanData[loanId].status = status;

        emit StatusUpdated(loanId, status);
    }

    function _updateCCR(uint256 loanId, uint32 newCcrBps) internal {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        if (loanId >= $.nextLoanId) revert LoanRegistryNonExistentLoanId(loanId);

        // TODO: default?
        if ($.mutableLoanData[loanId].status == LoanStatus.Closed) revert LoanRegistryAlreadyClosed(loanId);

        // TODO: are any additional assertions required, like `currentCcrBps < newCcrBps`?
        $.mutableLoanData[loanId].ccrBps = newCcrBps;

        emit CCRUpdated(loanId, newCcrBps);
    }

    // TODO: what is `location` precisely? won't `bytes32` be too restrictive?
    function _updateLocation(uint256 loanId, bytes32 newLocation) internal {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        if (loanId >= $.nextLoanId) revert LoanRegistryNonExistentLoanId(loanId);

        // TODO: default?
        if ($.mutableLoanData[loanId].status == LoanStatus.Closed) revert LoanRegistryAlreadyClosed(loanId);

        $.mutableLoanData[loanId].location = newLocation;

        emit LocationUpdated(loanId, newLocation);
    }

    function _setDefault(uint256 loanId) internal {
        LoanRegistryStorage storage $ = _getLoanRegistryStorage();
        if (loanId >= $.nextLoanId) revert LoanRegistryNonExistentLoanId(loanId);

        LoanStatus currentStatus = $.mutableLoanData[loanId].status;
        if (currentStatus > LoanStatus.WatchList) revert LoanRegistryWrongCurrentStatus(loanId, currentStatus);

        $.mutableLoanData[loanId].status = LoanStatus.Default;

        emit LoanDefaulted(loanId);
    }

    function _closeLoan(uint256 loanId, ClosureReason reason) internal {
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

    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address from) {
        from = super._update(to, tokenId, auth);
        if (from != address(0)) revert LoanRegistryNonTransferrable();
    }
}
