// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC20Burnable} from "../interfaces/IERC20Burnable.sol";

abstract contract WithdrawalQueueUpgradeable is Initializable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Burnable;

    struct WithdrawalQueueMetadata {
        // cumulative total of all withdrawal requests included the ones that have already been claimed
        uint256 queued;
        // cumulative total of all the requests that can be claimed including the ones that have already been claimed
        uint256 claimable;
        // total of all the requests that have been claimed
        uint256 claimed;
        // index of the next withdrawal request starting at 0
        uint256 nextWithdrawalIndex;
    }

    struct WithdrawalRequest {
        address withdrawer;
        bool claimed;
        uint88 timestamp;
        uint256 amount;
        uint256 queued;
    }

    event WithdrawalRequested(address indexed withdrawer, uint256 indexed requestId, uint256 amount, uint256 queued);
    event WithdrawalClaimed(address indexed withdrawer, uint256 indexed requestId, uint256 amount);
    event ClaimableIncreased(uint256 delta, uint256 newClaimable);

    error WithdrawalQueueZeroAmount();
    error WithdrawalQueueAlreadyClaimed();
    error WithdrawalQueueTooEarly();
    error WithdrawalQueueWrongClaimant();

    /// @custom:storage-location erc7201:pipeline.storage.WithdrawalQueue
    struct WithdrawalQueueStorage {
        WithdrawalQueueMetadata queueMetadata;
        IERC20Burnable fromToken;
        IERC20 intoToken;
        mapping(uint256 requestId => WithdrawalRequest) withdrawalRequests;
    }

    // keccak256(abi.encode(uint256(keccak256("pipeline.storage.WithdrawalQueue")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WithdrawalQueueStorageLocation =
        0x4cac70af0cf2a7940d95a04f5e319da114dcc73860d034caf69b06ca0a374600;

    function _getWithdrawalQueueStorage() private pure returns (WithdrawalQueueStorage storage $) {
        assembly {
            $.slot := WithdrawalQueueStorageLocation
        }
    }

    function __WithdrawalQueue_init(address _fromToken, address _intoToken) internal onlyInitializing {
        __WithdrawalQueue_init_unchained(_fromToken, _intoToken);
    }

    function __WithdrawalQueue_init_unchained(address _fromToken, address _intoToken) internal onlyInitializing {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        $.fromToken = IERC20Burnable(_fromToken);
        $.intoToken = IERC20(_intoToken);
    }

    function requestWithdrawal(uint256 amount) external virtual returns (uint256 requestId, uint256 queued) {
        if (amount == 0) revert WithdrawalQueueZeroAmount();
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        WithdrawalQueueMetadata storage metadata = $.queueMetadata;

        queued = metadata.queued + amount;
        requestId = metadata.nextWithdrawalIndex;

        $.withdrawalRequests[requestId] = WithdrawalRequest({
            withdrawer: msg.sender, claimed: false, timestamp: uint88(block.timestamp), amount: amount, queued: queued
        });

        metadata.queued = queued;
        unchecked {
            ++metadata.nextWithdrawalIndex;
        }

        $.fromToken.safeTransferFrom(msg.sender, address(this), amount);

        emit WithdrawalRequested(msg.sender, requestId, amount, queued);
    }

    function claimWithdrawal(uint256 requestId) external virtual returns (uint256 amount) {
        return _claimWithdrawal(requestId);
    }

    function fundWithdrawals(uint256 amount, address source) external virtual returns (uint256 claimable);

    function withdrawalRequests(uint256 requestId) external view returns (WithdrawalRequest memory) {
        return _getWithdrawalQueueStorage().withdrawalRequests[requestId];
    }

    function queueMetadata() external view returns (WithdrawalQueueMetadata memory) {
        return _getWithdrawalQueueStorage().queueMetadata;
    }

    function fromToken() external view returns (address) {
        return address(_getWithdrawalQueueStorage().fromToken);
    }

    function intoToken() external view returns (address) {
        return address(_getWithdrawalQueueStorage().intoToken);
    }

    function _claimWithdrawal(uint256 requestId) internal virtual returns (uint256 amount) {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        WithdrawalRequest storage request = $.withdrawalRequests[requestId];

        if (request.withdrawer != msg.sender) revert WithdrawalQueueWrongClaimant();
        if (request.claimed) revert WithdrawalQueueAlreadyClaimed();
        if (request.queued > $.queueMetadata.claimable) revert WithdrawalQueueTooEarly();

        amount = request.amount;
        request.claimed = true;
        $.queueMetadata.claimed += amount;

        $.intoToken.safeTransfer(msg.sender, amount);
        $.fromToken.burn(amount);

        emit WithdrawalClaimed(msg.sender, requestId, amount);
    }

    function _fundWithdrawals(uint256 amount, address source) internal virtual returns (uint256 claimable) {
        if (amount == 0) revert WithdrawalQueueZeroAmount();
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();

        claimable = $.queueMetadata.claimable + amount;
        $.queueMetadata.claimable = claimable;

        $.intoToken.safeTransferFrom(source, address(this), amount);

        emit ClaimableIncreased(amount, claimable);
    }
}
