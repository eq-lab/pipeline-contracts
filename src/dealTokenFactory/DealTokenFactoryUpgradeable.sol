// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IDealTokenFactory} from "../interfaces/IDealTokenFactory.sol";
import {ILoanRegistry} from "../interfaces/ILoanRegistry.sol";
import {DealToken} from "./DealToken.sol";

abstract contract DealTokenFactoryUpgradeable is AccessManagedUpgradeable, IDealTokenFactory {
    uint256 public constant MIN_DIGITS = 4;

    struct Deal {
        address debt;
    }

    event DealRegistered(uint256 indexed loanId, address debt);
    event DebtSynced(uint256 indexed loanId, uint256 target, uint256 previous, uint256 minted, uint256 clawed);
    event LoanRegistrySet(address loanRegistry);

    error DealTokenFactoryAlreadyRegistered(uint256 loanId);
    error DealTokenFactoryNotRegistered(uint256 loanId);
    error DealTokenFactoryZeroAddress();
    error DealTokenFactorySameValue();

    /// @custom:storage-location erc7201:pipeline.storage.DealTokenFactory
    struct DealTokenFactoryStorage {
        ILoanRegistry loanRegistry;
        mapping(uint256 loanId => Deal) deals;
    }

    // keccak256(abi.encode(uint256(keccak256("pipeline.storage.DealTokenFactory")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant DealTokenFactoryStorageLocation =
        0x443955876d9f39e0d361ae6e0cc08317ebc8681220385e114b1a79bfd8fbca00;

    function _getDealTokenFactoryStorage() private pure returns (DealTokenFactoryStorage storage $) {
        assembly {
            $.slot := DealTokenFactoryStorageLocation
        }
    }

    function __DealTokenFactory_init_unchained(address _loanRegistry) internal onlyInitializing {
        _setLoanRegistry(_getDealTokenFactoryStorage(), _loanRegistry);
    }

    function registerDeal(uint256 loanId) external restricted returns (Deal memory dealData) {
        DealTokenFactoryStorage storage $ = _getDealTokenFactoryStorage();
        _loanOutstanding($, loanId);
        if ($.deals[loanId].debt != address(0)) revert DealTokenFactoryAlreadyRegistered(loanId);

        (string memory name, string memory symbol) = _metadata(loanId);
        dealData.debt = address(new DealToken{salt: bytes32(loanId)}(name, symbol));
        $.deals[loanId] = dealData;

        emit DealRegistered(loanId, dealData.debt);
    }

    function syncDebt(uint256 loanId) external {
        DealTokenFactoryStorage storage $ = _getDealTokenFactoryStorage();
        DealToken debt = DealToken(_registeredDeal($, loanId).debt);

        uint256 target = _loanOutstanding($, loanId);
        address holder = IERC721(address($.loanRegistry)).ownerOf(loanId);

        uint256 previous = debt.balanceOf(holder);
        uint256 minted;
        uint256 clawed;
        if (target > previous) {
            minted = target - previous;
            debt.mint(holder, minted);
        } else if (previous > target) {
            clawed = previous - target;
            debt.burn(holder, clawed);
        }

        emit DebtSynced(loanId, target, previous, minted, clawed);
    }

    function setLoanRegistry(address newLoanRegistry) external restricted {
        _setLoanRegistry(_getDealTokenFactoryStorage(), newLoanRegistry);
    }

    function deal(uint256 loanId) external view returns (Deal memory) {
        return _registeredDeal(_getDealTokenFactoryStorage(), loanId);
    }

    function debtAddress(uint256 loanId) external view returns (address) {
        (string memory name, string memory symbol) = _metadata(loanId);
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(DealToken).creationCode, abi.encode(name, symbol)));
        return Create2.computeAddress(bytes32(loanId), initCodeHash);
    }

    function loanRegistry() external view returns (address) {
        return address(_getDealTokenFactoryStorage().loanRegistry);
    }

    function _setLoanRegistry(DealTokenFactoryStorage storage $, address newLoanRegistry) private {
        if (newLoanRegistry == address(0)) revert DealTokenFactoryZeroAddress();
        if (address($.loanRegistry) == newLoanRegistry) revert DealTokenFactorySameValue();
        $.loanRegistry = ILoanRegistry(newLoanRegistry);

        emit LoanRegistrySet(newLoanRegistry);
    }

    function _registeredDeal(DealTokenFactoryStorage storage $, uint256 loanId)
        private
        view
        returns (Deal storage dealData)
    {
        dealData = $.deals[loanId];
        if (dealData.debt == address(0)) revert DealTokenFactoryNotRegistered(loanId);
    }

    function _loanOutstanding(DealTokenFactoryStorage storage $, uint256 loanId) private view returns (uint256) {
        return $.loanRegistry.outstanding(loanId);
    }

    function _metadata(uint256 loanId) private pure returns (string memory name, string memory symbol) {
        string memory digits = Strings.toString(loanId);
        for (uint256 length = bytes(digits).length; length < MIN_DIGITS; ++length) {
            digits = string.concat("0", digits);
        }
        symbol = string.concat("DEBT", digits);
        name = string.concat("Pipeline ", symbol);
    }
}
