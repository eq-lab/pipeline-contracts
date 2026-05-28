// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IERC20Managed} from "./interfaces/IERC20Managed.sol";
import {ILoanRegistry} from "./interfaces/ILoanRegistry.sol";

contract PipelineYieldMinter is AccessManaged {
    ILoanRegistry public immutable loanRegistry;
    IERC20Managed public immutable plUsd;
    address public immutable stakedPlUsd;
    address public treasury;

    struct YieldMint {
        uint256 amount;
        uint256 nonce;
    }

    event YieldMinted(uint256 sPlUsdAmount, uint256 treasuryAmount);

    error YieldMinterForbiddenMint(uint256 loanId, uint256 repaymentId);

    constructor(address _authority, address _stakedPlUsd, address _loanRegistry, address _treasury)
        AccessManaged(_authority)
    {
        stakedPlUsd = _stakedPlUsd;
        plUsd = IERC20Managed(IERC4626(_stakedPlUsd).asset());

        loanRegistry = ILoanRegistry(_loanRegistry);
        treasury = _treasury;
    }

    function mintYield(uint256 loanId, uint256 repaymentId) external restricted {
        ILoanRegistry _loanRegistry = loanRegistry;
        if (!_loanRegistry.canYieldBeMinted(loanId, repaymentId)) revert YieldMinterForbiddenMint(loanId, repaymentId);
        ILoanRegistry.RepaymentData memory repaymentData = _loanRegistry.repaymentData(loanId, repaymentId);

        uint256 sPlUsdAmount = repaymentData.seniorInterest;
        uint256 treasuryAmount = repaymentData.mgmtFee + repaymentData.perfFee + repaymentData.oetAlloc;

        _executeMintYield(sPlUsdAmount, treasuryAmount);

        _loanRegistry.markMinted(loanId, repaymentId);
    }

    function _executeMintYield(uint256 sPlUsdAmount, uint256 treasuryAmount) private {
        plUsd.mint(stakedPlUsd, sPlUsdAmount);
        plUsd.mint(treasury, treasuryAmount);

        emit YieldMinted(sPlUsdAmount, treasuryAmount);
    }
}
