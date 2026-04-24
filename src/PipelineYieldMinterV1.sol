// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IERC20Managed} from "./interfaces/IERC20Managed.sol";

contract PipelineYieldMinterV1 is EIP712, AccessManaged {
    using ECDSA for bytes32;

    address public mintAuthority;
    uint256 public nextNonce;
    address public stakedPlUsd;
    IERC20Managed public plUsd;

    bytes32 public constant YIELD_MINT_TYPEHASH = keccak256("YieldMint(uint256 amount,uint256 nonce)");

    struct YieldMint {
        uint256 amount;
        uint256 nonce;
    }

    event YieldMinted(uint256 amount);

    error PipelineYieldMinterV1UnauthorizedSigner(address recovered);
    error PipelineYieldMinterV1ZeroAmount();

    constructor(address _authority, address _mintAuthority, address _stakedPlUsd)
        EIP712("PipelineYieldMinter", "1")
        AccessManaged(_authority)
    {
        mintAuthority = _mintAuthority;
        stakedPlUsd = _stakedPlUsd;
        plUsd = IERC20Managed(IERC4626(_stakedPlUsd).asset());
    }

    function mintYield(uint256 yieldAmount, bytes calldata signature) external restricted {
        if (yieldAmount == 0) revert PipelineYieldMinterV1ZeroAmount();
        uint256 nonce = nextNonce++;
        address recovered = _recoverSignature(yieldAmount, nonce, signature);
        if (recovered != mintAuthority) {
            revert PipelineYieldMinterV1UnauthorizedSigner(recovered);
        }

        _executeMintYield(yieldAmount);
    }

    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function _executeMintYield(uint256 amount) private {
        plUsd.mint(stakedPlUsd, amount);
        emit YieldMinted(amount);
    }

    function _recoverSignature(uint256 yieldAmount, uint256 nonce, bytes calldata signature)
        private
        view
        returns (address)
    {
        bytes32 dataHash = keccak256(abi.encode(YIELD_MINT_TYPEHASH, yieldAmount, nonce));
        bytes32 digest = _hashTypedDataV4(dataHash);
        return digest.recover(signature);
    }
}
