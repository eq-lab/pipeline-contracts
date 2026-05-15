// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

import {IERC20Managed} from "../interfaces/IERC20Managed.sol";
import {VerifiedRequestsQueueUpgradeable} from "../requestsQueue/VerifiedRequestsQueueUpgradeable.sol";

contract DepositManagerUpgradeable is AccessManagedUpgradeable, VerifiedRequestsQueueUpgradeable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Managed;

    event DepositRequested(uint256 indexed requestId, address indexed user, uint256 amount);
    event CustodianSet(address newCustodian);
    event MinDepositSet(uint256 newMinDeposit);

    error DepositManagerLessThanMinAmount();
    error DepositManagerSameValue();
    error DepositManagerZeroAddress();

    /// @custom:storage-location erc7201:pipeline.storage.DepositManager
    struct DepositManagerStorage {
        uint256 minDeposit;
        address custodian;
        IERC20 asset;
        IERC20Managed share;
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
        string memory name,
        string memory version,
        address verifier,
        address _custodian,
        address asset,
        address share,
        uint256 _minDeposit
    ) internal onlyInitializing {
        __AccessManaged_init(authority);
        __VerifiedRequestsQueue_init(name, version, verifier);
        __DepositManager_init_unchained(_custodian, asset, share, _minDeposit);
    }

    function __DepositManager_init_unchained(address _custodian, address asset, address share, uint256 _minDeposit)
        internal
        onlyInitializing
    {
        DepositManagerStorage storage $ = _getDepositManagerStorage();
        $.custodian = _custodian;
        $.asset = IERC20(asset);
        $.share = IERC20Managed(share);
        $.minDeposit = _minDeposit;
    }

    function requestDeposit(uint256 amount) external returns (uint256 requestId) {
        return _requestDeposit(amount);
    }

    function claimDeposit(uint256 requestId, bytes calldata verifierSignature) external returns (uint256 amount) {
        return _claimDeposit(requestId, verifierSignature);
    }

    function setCustodian(address _custodian) external restricted {
        if (_custodian == address(0)) revert DepositManagerZeroAddress();

        DepositManagerStorage storage $ = _getDepositManagerStorage();
        if ($.custodian == _custodian) revert DepositManagerSameValue();

        _getDepositManagerStorage().custodian = _custodian;

        emit CustodianSet(_custodian);
    }

    function setMinDeposit(uint256 _minDeposit) external restricted {
        DepositManagerStorage storage $ = _getDepositManagerStorage();

        if ($.minDeposit == _minDeposit) revert DepositManagerSameValue();
        $.minDeposit = _minDeposit;

        emit MinDepositSet(_minDeposit);
    }

    function setVerifier(address verifier) external restricted {
        _setVerifier(verifier);
    }

    function minDeposit() external view returns (uint256) {
        return _getDepositManagerStorage().minDeposit;
    }

    function custodian() external view returns (address) {
        return _getDepositManagerStorage().custodian;
    }

    function _requestDeposit(uint256 amount) internal returns (uint256 requestId) {
        _preDepositHook(amount);

        requestId = _enqueueRequest(msg.sender, amount);

        DepositManagerStorage storage $ = _getDepositManagerStorage();
        $.asset.safeTransferFrom(msg.sender, $.custodian, amount);

        emit DepositRequested(requestId, msg.sender, amount);
    }

    function _claimDeposit(uint256 requestId, bytes calldata verifierSignature) internal returns (uint256 amount) {
        amount = _claimRequest(requestId, verifierSignature);

        DepositManagerStorage storage $ = _getDepositManagerStorage();
        $.share.mint(msg.sender, amount);
    }

    function _preDepositHook(uint256 amount) internal virtual {
        DepositManagerStorage storage $ = _getDepositManagerStorage();
        if (amount < $.minDeposit) revert DepositManagerLessThanMinAmount();
    }

    function _asset() internal view returns (address) {
        return address(_getDepositManagerStorage().asset);
    }

    function _share() internal view returns (address) {
        return address(_getDepositManagerStorage().share);
    }
}
