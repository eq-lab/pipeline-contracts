// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {PipelineUSD} from "../src/PipelineUSD.sol";
import {StakedPipelineUSD} from "../src/StakedPipelineUSD.sol";
import {WhitelistRegistry} from "../src/WhitelistRegistry.sol";
import {PipelineDepositManager} from "../src/PipelineDepositManager.sol";
import {PipelineWithdrawalQueue} from "../src/PipelineWithdrawalQueue.sol";
import {PipelineLoanRegistry} from "../src/PipelineLoanRegistry.sol";
import {PipelineYieldMinterV1} from "../src/PipelineYieldMinterV1.sol";

import {WhitelistAccessUpgradeable} from "../src/whitelist/WhitelistAccessUpgradeable.sol";
import {DepositManagerUpgradeable} from "../src/depositManager/DepositManagerUpgradeable.sol";
import {RateLimiterUpgradeable} from "../src/depositManager/RateLimiterUpgradeable.sol";
import {WithdrawalQueueUpgradeable} from "../src/withdrawalQueue/WithdrawalQueueUpgradeable.sol";
import {WithdrawalQueueShutdownUpgradeable} from "../src/withdrawalQueue/WithdrawalQueueShutdownUpgradeable.sol";
import {VerifiedRequestsQueueUpgradeable} from "../src/requestsQueue/VerifiedRequestsQueueUpgradeable.sol";

import {USDCMock} from "./mocks/USDCMock.t.sol";

contract PipelineTestSetUp is Test {
    AccessManager public authority;
    WhitelistRegistry public whitelistRegistry;
    PipelineUSD public plUsd;
    StakedPipelineUSD public sPlUsd;
    PipelineYieldMinterV1 public yieldMinter;
    PipelineDepositManager public depositManager;
    PipelineWithdrawalQueue public withdrawalQueue;
    PipelineLoanRegistry public loanRegistry;
    USDCMock public usdc = new USDCMock();

    uint256 yieldMinterAuthorityPrivateKey = uint256(bytes32("yieldMinterAuthority"));
    uint256 depositVerifierPrivateKey = uint256(bytes32("depositVerifier"));
    uint256 withdrawalVerifierPrivateKey = uint256(bytes32("withdrawalVerifier"));

    address public admin = makeAddr("admin");
    address public upgrader = makeAddr("upgrader");
    address public pauser = makeAddr("pauser");
    address public whitelistAdmin = makeAddr("whitelistAdmin");
    address public yieldMinterAuthority = vm.addr(yieldMinterAuthorityPrivateKey);
    address public yieldMinterManager = makeAddr("yieldMinterManager");
    address public depositManagerAdmin = makeAddr("depositManagerAdmin");
    address public depositVerifier = vm.addr(depositVerifierPrivateKey);
    address public queueManager = makeAddr("queueManager");
    address public withdrawalVerifier = vm.addr(withdrawalVerifierPrivateKey);
    address public loanRegistryManager = makeAddr("loanRegistryManager");
    address public custodian = makeAddr("custodian");
    address public tokenHolder = makeAddr("tokenHolder");

    uint256 minDeposit = 1_000_000_000;
    RateLimiterUpgradeable.RateLimitConfig public rateLimitConfigDefault = RateLimiterUpgradeable.RateLimitConfig({
        txLimit: 5_000_000_000_000, windowLimit: 10_000_000_000_000, window: 86400 * 7, shift: 86400 * 3
    });

    function setUp() public virtual {
        _setUpAuthority();
        _setUpWhitelistRegistry();
        _setUpPlUsd();
        _setUpSPlUsd();
        _setUpYieldMinter();
        _setupLoanRegistry();

        _setUpYieldMinterManager();
        _setUpPauser();
        _setUpWhitelistAdmin();
        _setupLoanRegistryManager();

        _setUpDepositManager();
        _setUpDepositManagerAdmin();

        _setupWithdrawalQueue();
        _setUpQueueManager();

        _setUpUpgrader();
    }

    function _setUpAuthority() private {
        authority = new AccessManager(admin);
    }

    function _setUpWhitelistRegistry() private {
        WhitelistRegistry implementation = new WhitelistRegistry();
        bytes memory data = abi.encodeWithSelector(WhitelistRegistry.initialize.selector, address(authority));
        whitelistRegistry = WhitelistRegistry(address(new ERC1967Proxy(address(implementation), data)));
    }

    function _setUpPlUsd() private {
        PipelineUSD implementation = new PipelineUSD();
        bytes memory data =
            abi.encodeWithSelector(PipelineUSD.initialize.selector, address(authority), address(whitelistRegistry));
        plUsd = PipelineUSD(address(new ERC1967Proxy(address(implementation), data)));
    }

    function _setUpSPlUsd() private {
        StakedPipelineUSD implementation = new StakedPipelineUSD();
        bytes memory data = abi.encodeWithSelector(StakedPipelineUSD.initialize.selector, plUsd, address(authority));
        sPlUsd = StakedPipelineUSD(address(new ERC1967Proxy(address(implementation), data)));
    }

    function _setUpYieldMinter() private {
        yieldMinter = new PipelineYieldMinterV1(address(authority), yieldMinterAuthority, address(sPlUsd));
        uint64 roleId = uint64(bytes8(keccak256("MINTER")));

        vm.prank(admin);
        authority.grantRole(roleId, address(yieldMinter), 0);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = PipelineUSD.mint.selector;

        vm.prank(admin);
        authority.setTargetFunctionRole(address(plUsd), selectors, roleId);
    }

    function _setUpDepositManager() private {
        PipelineDepositManager implementation = new PipelineDepositManager();
        bytes memory data = abi.encodeWithSelector(
            PipelineDepositManager.initialize.selector,
            authority,
            depositVerifier,
            custodian,
            usdc,
            plUsd,
            minDeposit,
            rateLimitConfigDefault
        );
        depositManager = PipelineDepositManager(address(new ERC1967Proxy(address(implementation), data)));

        uint64 roleId = uint64(bytes8(keccak256("MINTER")));

        vm.prank(admin);
        authority.grantRole(roleId, address(depositManager), 0);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = PipelineUSD.mint.selector;

        vm.prank(admin);
        authority.setTargetFunctionRole(address(plUsd), selectors, roleId);
    }

    function _setupWithdrawalQueue() private {
        PipelineWithdrawalQueue implementation = new PipelineWithdrawalQueue();
        bytes memory data = abi.encodeWithSelector(
            PipelineWithdrawalQueue.initialize.selector,
            address(authority),
            withdrawalVerifier,
            address(plUsd),
            address(usdc),
            tokenHolder
        );
        withdrawalQueue = PipelineWithdrawalQueue(address(new ERC1967Proxy(address(implementation), data)));

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowSystemAddress(address(withdrawalQueue));

        uint64 roleId = uint64(bytes8(keccak256("BURNER")));

        vm.prank(admin);
        authority.grantRole(roleId, address(withdrawalQueue), 0);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = PipelineUSD.burn.selector;

        vm.prank(admin);
        authority.setTargetFunctionRole(address(plUsd), selectors, roleId);
    }

    function _setupLoanRegistry() private {
        PipelineLoanRegistry implementation = new PipelineLoanRegistry();
        bytes memory data = abi.encodeWithSelector(
            PipelineLoanRegistry.initialize.selector, address(authority), "Loan registry name", "Loan registry symbol"
        );
        loanRegistry = PipelineLoanRegistry(address(new ERC1967Proxy(address(implementation), data)));
    }

    function _setUpYieldMinterManager() private {
        uint64 roleId = uint64(bytes8(keccak256("YIELD_MINTER_MANAGER")));

        vm.prank(admin);
        authority.grantRole(roleId, yieldMinterManager, 0);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = PipelineYieldMinterV1.mintYield.selector;

        vm.prank(admin);
        authority.setTargetFunctionRole(address(yieldMinter), selectors, roleId);
    }

    function _setUpPauser() private {
        uint64 roleId = uint64(bytes8(keccak256("PAUSER_ROLE")));

        vm.prank(admin);
        authority.grantRole(roleId, pauser, 0);

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = PipelineUSD.pause.selector;
        selectors[1] = PipelineUSD.unpause.selector;

        vm.prank(admin);
        authority.setTargetFunctionRole(address(plUsd), selectors, roleId);
    }

    function _setUpUpgrader() private {
        uint64 roleId = uint64(bytes8(keccak256("UPGRADER_ROLE")));

        vm.prank(admin);
        authority.grantRole(roleId, upgrader, 0);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = UUPSUpgradeable.upgradeToAndCall.selector;

        vm.prank(admin);
        authority.setTargetFunctionRole(address(plUsd), selectors, roleId);

        vm.prank(admin);
        authority.setTargetFunctionRole(address(sPlUsd), selectors, roleId);

        vm.prank(admin);
        authority.setTargetFunctionRole(address(whitelistRegistry), selectors, roleId);

        vm.prank(admin);
        authority.setTargetFunctionRole(address(depositManager), selectors, roleId);

        vm.prank(admin);
        authority.setTargetFunctionRole(address(withdrawalQueue), selectors, roleId);

        vm.prank(admin);
        authority.setTargetFunctionRole(address(loanRegistry), selectors, roleId);
    }

    function _setUpWhitelistAdmin() private {
        uint64 roleId = uint64(bytes8(keccak256("WHITELIST_ADMIN_ROLE")));

        vm.prank(admin);
        authority.grantRole(roleId, whitelistAdmin, 0);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = WhitelistAccessUpgradeable.allowSystemAddress.selector;
        selectors[1] = WhitelistAccessUpgradeable.allowUser.selector;
        selectors[2] = WhitelistAccessUpgradeable.disallow.selector;

        vm.prank(admin);
        authority.setTargetFunctionRole(address(whitelistRegistry), selectors, roleId);
    }

    function _setUpDepositManagerAdmin() private {
        uint64 roleId = uint64(bytes8(keccak256("DEPOSIT_MANAGER_ADMIN")));
        vm.prank(admin);
        authority.grantRole(roleId, depositManagerAdmin, 0);

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = DepositManagerUpgradeable.setMinDeposit.selector;
        selectors[1] = DepositManagerUpgradeable.setCustodian.selector;
        selectors[2] = DepositManagerUpgradeable.setVerifier.selector;
        selectors[3] = RateLimiterUpgradeable.increaseTxLimit.selector;
        selectors[4] = RateLimiterUpgradeable.decreaseTxLimit.selector;
        selectors[5] = RateLimiterUpgradeable.increaseWindowLimit.selector;
        selectors[6] = RateLimiterUpgradeable.decreaseWindowLimit.selector;

        vm.prank(admin);
        authority.setTargetFunctionRole(address(depositManager), selectors, roleId);
    }

    function _setUpQueueManager() private {
        uint64 roleId = uint64(bytes8(keccak256("WITHDRAWAL_QUEUE_MANAGER_ROLE")));

        vm.prank(admin);
        authority.grantRole(roleId, queueManager, 0);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = WithdrawalQueueUpgradeable.changeIntoTokenHolder.selector;
        selectors[1] = WithdrawalQueueShutdownUpgradeable.setShutdownRate.selector;
        selectors[2] = WithdrawalQueueShutdownUpgradeable.setVerifier.selector;

        vm.prank(admin);
        authority.setTargetFunctionRole(address(withdrawalQueue), selectors, roleId);
    }

    function _setupLoanRegistryManager() private {
        uint64 roleId = uint64(bytes8(keccak256("LOAN_REGISTRY_MANAGER")));

        vm.prank(admin);
        authority.grantRole(roleId, loanRegistryManager, 0);

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = PipelineLoanRegistry.mintLoan.selector;
        selectors[1] = PipelineLoanRegistry.updateStatus.selector;
        selectors[2] = PipelineLoanRegistry.updateCCR.selector;
        selectors[3] = PipelineLoanRegistry.updateLocation.selector;
        selectors[4] = PipelineLoanRegistry.setDefault.selector;
        selectors[5] = PipelineLoanRegistry.closeLoan.selector;
        selectors[6] = PipelineLoanRegistry.recordPayment.selector;

        vm.prank(admin);
        authority.setTargetFunctionRole(address(loanRegistry), selectors, roleId);
    }
}
