// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

import {IERC20Managed} from "../interfaces/IERC20Managed.sol";

contract DepositManagerUpgradeable is Initializable, AccessManagedUpgradeable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Managed;

    /// @custom:storage-location erc7201:pipeline.storage.DepositManager
    struct DepositManagerStorage {
        uint256 minDeposit;
        address custodian;
        IERC20 fromToken;
        IERC20Managed intoToken;
    }

    // keccak256(abi.encode(uint256(keccak256("pipeline.storage.DepositManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant DepositManagerStorageLocation =
        0x1c33cd770dcb3de84120ccdf3090375782c0f19655e1ffbdbfcea4ab9b429900;

    function _getDepositManagerStorage() private pure returns (DepositManagerStorage storage $) {
        assembly {
            $.slot := DepositManagerStorageLocation
        }
    }

    function __DepositManager_init(
        address authority,
        address _custodian,
        address _fromToken,
        address _intoToken,
        uint256 _minDeposit
    ) internal onlyInitializing {
        __AccessManaged_init(authority);
        __DepositManager_init_unchained(_custodian, _fromToken, _intoToken, _minDeposit);
    }

    function __DepositManager_init_unchained(
        address _custodian,
        address _fromToken,
        address _intoToken,
        uint256 _minDeposit
    ) internal onlyInitializing {
        DepositManagerStorage storage $ = _getDepositManagerStorage();
        $.custodian = _custodian;
        $.fromToken = IERC20(_fromToken);
        $.intoToken = IERC20Managed(_intoToken);
        $.minDeposit = _minDeposit;
    }

    function deposit(uint256 amount) external {
        _deposit(amount);
    }

    function setCustodian(address _custodian) external restricted {
        _getDepositManagerStorage().custodian = _custodian;
    }

    function setMinDeposit(uint256 _minDeposit) external restricted {
        DepositManagerStorage storage $ = _getDepositManagerStorage();

        if ($.minDeposit == _minDeposit) revert();

        $.minDeposit = _minDeposit;
    }

    function minDeposit() external view returns (uint256) {
        return _getDepositManagerStorage().minDeposit;
    }

    function custodian() external view returns (address) {
        return _getDepositManagerStorage().custodian;
    }

    function _deposit(uint256 amount) internal {
        _preDepositHook(amount);

        DepositManagerStorage storage $ = _getDepositManagerStorage();
        $.fromToken.safeTransferFrom(msg.sender, $.custodian, amount);
        $.intoToken.mint(msg.sender, amount);
    }

    function _preDepositHook(uint256 amount) internal virtual {
        if (amount == 0) revert();

        DepositManagerStorage storage $ = _getDepositManagerStorage();
        if (amount < $.minDeposit) revert();
    }
}
