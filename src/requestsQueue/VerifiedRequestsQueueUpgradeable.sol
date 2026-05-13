// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IERC20Managed} from "../interfaces/IERC20Managed.sol";

abstract contract VerifiedRequestsQueueUpgradeable is EIP712Upgradeable {
    using ECDSA for bytes32;

    struct Request {
        uint256 amount;
        address user;
        uint88 timestamp;
        bool claimed;
    }

    bytes32 public constant VERIFIED_REQUESTS_TYPEHASH =
        keccak256("VerifiedRequests(uint256 requestId,address user,uint256 amount)");

    event RequestEnqueued(uint256 indexed requestId, address indexed user, uint256 amount, uint88 timestamp);
    event RequestClaimed(uint256 indexed requestId, address indexed user, uint256 amount);
    event VerifierSet(address indexed newVerifier);

    error VerifiedRequestsQueueAlreadyClaimed();
    error VerifiedRequestsInvalidSignature();
    error VerifiedRequestsInvalidSender();
    error VerifiedRequestsInvalidRequestId();
    error VerifiedRequestsQueueZeroAmount();
    error VerifiedRequestsZeroAddress();
    error VerifiedRequestsSameValue();

    /// @custom:storage-location erc7201:pipeline.storage.VerifiedRequestsQueue
    struct VerifiedRequestsQueueStorage {
        uint256 nextRequestId;
        address verifier;
        mapping(uint256 requestId => Request) requests;
    }

    // keccak256(abi.encode(uint256(keccak256("pipeline.storage.VerifiedRequestsQueue")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VerifiedRequestsQueueStorageLocation =
        0x5525682345ab4fee305c5fbbbf2cef1856c4d99c1e66571924b26aea90b5c700;

    function _getVerifiedRequestsQueueStorage() private pure returns (VerifiedRequestsQueueStorage storage $) {
        assembly {
            $.slot := VerifiedRequestsQueueStorageLocation
        }
    }

    function __VerifiedRequestsQueue_init(string memory name, string memory version, address _verifier)
        internal
        onlyInitializing
    {
        __EIP712_init(name, version);
        __VerifiedRequestsQueue_init_unchained(_verifier);
    }

    function __VerifiedRequestsQueue_init_unchained(address _verifier) internal onlyInitializing {
        _setVerifier(_verifier);
    }

    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function nextRequestId() external view returns (uint256) {
        return _getVerifiedRequestsQueueStorage().nextRequestId;
    }

    function verifier() external view returns (address) {
        return _getVerifiedRequestsQueueStorage().verifier;
    }

    function requests(uint256 requestId) public view returns (Request memory) {
        return _getVerifiedRequestsQueueStorage().requests[requestId];
    }

    function verifySignature(uint256 requestId, bytes calldata verifierSignature) external view returns (bool) {
        VerifiedRequestsQueueStorage storage $ = _getVerifiedRequestsQueueStorage();
        Request storage request = $.requests[requestId];

        uint256 amount = request.amount;
        if (amount == 0) return false;

        return _verifySignature(requestId, request.user, amount, verifierSignature);
    }

    function _enqueueRequest(address user, uint256 amount) internal returns (uint256 requestId) {
        if (amount == 0) revert VerifiedRequestsQueueZeroAmount();

        VerifiedRequestsQueueStorage storage $ = _getVerifiedRequestsQueueStorage();

        requestId = $.nextRequestId;
        uint88 timestamp = uint88(block.timestamp);

        $.requests[requestId] = Request({amount: amount, user: user, timestamp: timestamp, claimed: false});

        unchecked {
            ++$.nextRequestId;
        }

        emit RequestEnqueued(requestId, user, amount, timestamp);
    }

    function _claimRequest(uint256 requestId, bytes calldata verifierSignature) internal returns (uint256 amount) {
        VerifiedRequestsQueueStorage storage $ = _getVerifiedRequestsQueueStorage();
        Request storage request = $.requests[requestId];

        amount = request.amount;
        if (amount == 0) revert VerifiedRequestsInvalidRequestId();

        address user = request.user;
        if (msg.sender != user) revert VerifiedRequestsInvalidSender();

        if (request.claimed) revert VerifiedRequestsQueueAlreadyClaimed();
        if (!_verifySignature(requestId, user, amount, verifierSignature)) revert VerifiedRequestsInvalidSignature();

        request.claimed = true;

        emit RequestClaimed(requestId, user, amount);
    }

    function _setVerifier(address newVerifier) internal {
        if (newVerifier == address(0)) revert VerifiedRequestsZeroAddress();

        VerifiedRequestsQueueStorage storage $ = _getVerifiedRequestsQueueStorage();
        if (newVerifier == $.verifier) revert VerifiedRequestsSameValue();

        $.verifier = newVerifier;

        emit VerifierSet(newVerifier);
    }

    function _verifySignature(uint256 requestId, address user, uint256 amount, bytes calldata verifierSignature)
        private
        view
        returns (bool)
    {
        VerifiedRequestsQueueStorage storage $ = _getVerifiedRequestsQueueStorage();
        address recovered = _recoverSignature(requestId, user, amount, verifierSignature);

        return $.verifier == recovered;
    }

    function _recoverSignature(uint256 requestId, address user, uint256 amount, bytes calldata verifierSignature)
        private
        view
        returns (address)
    {
        bytes32 dataHash = keccak256(abi.encode(VERIFIED_REQUESTS_TYPEHASH, requestId, user, amount));
        bytes32 digest = _hashTypedDataV4(dataHash);
        return digest.recover(verifierSignature);
    }
}
