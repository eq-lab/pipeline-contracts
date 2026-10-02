// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {ICollateralRegistry} from "../interfaces/ICollateralRegistry.sol";
import {IDealTokenFactory} from "../interfaces/IDealTokenFactory.sol";
import {ILoanRegistry} from "../interfaces/ILoanRegistry.sol";
import {DealToken} from "./DealToken.sol";

abstract contract DealTokenFactoryUpgradeable is AccessManagedUpgradeable, IDealTokenFactory {
    uint256 public constant MIN_DIGITS = 4;

    struct Deal {
        address debt;
        address cargo;
    }

    event DealRegistered(uint256 indexed loanId, address debt, address cargo);
    event DebtSynced(uint256 indexed loanId, uint256 target, uint256 previous, uint256 minted, uint256 clawed);
    event CargoSynced(uint256 indexed loanId, uint256 target, uint256 previous, uint256 minted, uint256 burned);
    event LoanRegistrySet(address loanRegistry);
    event CollateralRegistrySet(address collateralRegistry);

    error DealTokenFactoryAlreadyRegistered(uint256 loanId);
    error DealTokenFactoryNotRegistered(uint256 loanId);
    error DealTokenFactoryZeroAddress();
    error DealTokenFactorySameValue();

    /// @custom:storage-location erc7201:pipeline.storage.DealTokenFactory
    struct DealTokenFactoryStorage {
        ILoanRegistry loanRegistry;
        ICollateralRegistry collateralRegistry;
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

    function __DealTokenFactory_init_unchained(address _loanRegistry, address _collateralRegistry)
        internal
        onlyInitializing
    {
        DealTokenFactoryStorage storage $ = _getDealTokenFactoryStorage();
        _setLoanRegistry($, _loanRegistry);
        _setCollateralRegistry($, _collateralRegistry);
    }

    function registerDeal(uint256 loanId) external restricted returns (Deal memory dealData) {
        DealTokenFactoryStorage storage $ = _getDealTokenFactoryStorage();
        $.loanRegistry.outstanding(loanId);
        if ($.deals[loanId].debt != address(0)) revert DealTokenFactoryAlreadyRegistered(loanId);

        bytes32 salt = bytes32(loanId);
        (string memory debtName, string memory debtSymbol) = _metadata("DEBT", loanId);
        (string memory cargoName, string memory cargoSymbol) = _metadata("CARGO", loanId);

        dealData.debt = address(new DealToken{salt: salt}(debtName, debtSymbol));
        dealData.cargo = address(new DealToken{salt: salt}(cargoName, cargoSymbol));
        $.deals[loanId] = dealData;

        emit DealRegistered(loanId, dealData.debt, dealData.cargo);
    }

    function syncDebt(uint256 loanId) external {
        DealTokenFactoryStorage storage $ = _getDealTokenFactoryStorage();
        DealToken debt = DealToken(_registeredDeal($, loanId).debt);

        ILoanRegistry _loanRegistry = $.loanRegistry;
        uint256 target = _loanRegistry.outstanding(loanId);
        address holder = IERC721(address(_loanRegistry)).ownerOf(loanId);

        (uint256 previous, uint256 minted, uint256 clawed) = _sync(debt, holder, target);

        emit DebtSynced(loanId, target, previous, minted, clawed);
    }

    function syncCargo(uint256 loanId) external {
        DealTokenFactoryStorage storage $ = _getDealTokenFactoryStorage();
        DealToken cargo = DealToken(_registeredDeal($, loanId).cargo);

        uint256 target = $.collateralRegistry.cargoQuantity(loanId);
        (uint256 previous, uint256 minted, uint256 burned) = _sync(cargo, address(this), target);

        emit CargoSynced(loanId, target, previous, minted, burned);
    }

    function setLoanRegistry(address newLoanRegistry) external restricted {
        _setLoanRegistry(_getDealTokenFactoryStorage(), newLoanRegistry);
    }

    function setCollateralRegistry(address newCollateralRegistry) external restricted {
        _setCollateralRegistry(_getDealTokenFactoryStorage(), newCollateralRegistry);
    }

    function deal(uint256 loanId) external view returns (Deal memory) {
        return _registeredDeal(_getDealTokenFactoryStorage(), loanId);
    }

    function debtAddress(uint256 loanId) external view returns (address) {
        return _predictAddress("DEBT", loanId);
    }

    function cargoAddress(uint256 loanId) external view returns (address) {
        return _predictAddress("CARGO", loanId);
    }

    function loanRegistry() external view returns (address) {
        return address(_getDealTokenFactoryStorage().loanRegistry);
    }

    function collateralRegistry() external view returns (address) {
        return address(_getDealTokenFactoryStorage().collateralRegistry);
    }

    function _sync(DealToken token, address holder, uint256 target)
        private
        returns (uint256 previous, uint256 minted, uint256 burned)
    {
        previous = token.balanceOf(holder);
        if (target > previous) {
            minted = target - previous;
            token.mint(holder, minted);
        } else if (previous > target) {
            burned = previous - target;
            token.burn(holder, burned);
        }
    }

    function _setLoanRegistry(DealTokenFactoryStorage storage $, address newLoanRegistry) private {
        if (newLoanRegistry == address(0)) revert DealTokenFactoryZeroAddress();
        if (address($.loanRegistry) == newLoanRegistry) revert DealTokenFactorySameValue();
        $.loanRegistry = ILoanRegistry(newLoanRegistry);

        emit LoanRegistrySet(newLoanRegistry);
    }

    function _setCollateralRegistry(DealTokenFactoryStorage storage $, address newCollateralRegistry) private {
        if (newCollateralRegistry == address(0)) revert DealTokenFactoryZeroAddress();
        if (address($.collateralRegistry) == newCollateralRegistry) revert DealTokenFactorySameValue();
        $.collateralRegistry = ICollateralRegistry(newCollateralRegistry);

        emit CollateralRegistrySet(newCollateralRegistry);
    }

    function _registeredDeal(DealTokenFactoryStorage storage $, uint256 loanId)
        private
        view
        returns (Deal storage dealData)
    {
        dealData = $.deals[loanId];
        if (dealData.debt == address(0)) revert DealTokenFactoryNotRegistered(loanId);
    }

    function _predictAddress(string memory prefix, uint256 loanId) private view returns (address) {
        (string memory name, string memory symbol) = _metadata(prefix, loanId);
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(DealToken).creationCode, abi.encode(name, symbol)));
        return Create2.computeAddress(bytes32(loanId), initCodeHash);
    }

    function _metadata(string memory prefix, uint256 loanId)
        private
        pure
        returns (string memory name, string memory symbol)
    {
        string memory digits = Strings.toString(loanId);
        for (uint256 length = bytes(digits).length; length < MIN_DIGITS; ++length) {
            digits = string.concat("0", digits);
        }
        symbol = string.concat(prefix, digits);
        name = string.concat("Pipeline ", symbol);
    }
}
