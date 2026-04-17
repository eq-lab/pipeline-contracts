// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {PipelineUSD} from "../src/PipelineUSD.sol";
import {StakedPipelineUSD} from "../src/StakedPipelineUSD.sol";
import {WhitelistRegistry} from "../src/WhitelistRegistry.sol";
import {PipelineWithdrawalQueue} from "../src/PipelineWithdrawalQueue.sol";
import {WhitelistAccessUpgradeable} from "../src/whitelist/WhitelistAccessUpgradeable.sol";
import {WithdrawalQueueUpgradeable} from "../src/withdrawalQueue/WithdrawalQueueUpgradeable.sol";

import {USDCMock} from "./mocks/USDCMock.t.sol";

contract PipelineTestSetUp is Test {
    AccessManager public authority;
    WhitelistRegistry public whitelistRegistry;
    PipelineUSD public plUsd;
    StakedPipelineUSD public sPlUsd;
    PipelineWithdrawalQueue public withdrawalQueue;
    USDCMock public usdc = new USDCMock();

    address public admin = makeAddr("admin");
    address public trustee = makeAddr("trustee");
    address public upgrader = makeAddr("upgrader");
    address public pauser = makeAddr("pauser");
    address public whitelistAdmin = makeAddr("whitelistAdmin");
    address public queueManager = makeAddr("queueManager");

    function setUp() public virtual {
        _setUpAuthority();
        _setUpWhitelistRegistry();
        _setUpPlUsd();
        _setUpSPlUsd();

        _setUpTrustee();
        _setUpPauser();
        _setUpWhitelistAdmin();

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

    function _setupWithdrawalQueue() private {
        PipelineWithdrawalQueue implementation = new PipelineWithdrawalQueue();
        bytes memory data = abi.encodeWithSelector(
            PipelineWithdrawalQueue.initialize.selector, address(authority), address(plUsd), address(usdc)
        );
        withdrawalQueue = PipelineWithdrawalQueue(address(new ERC1967Proxy(address(implementation), data)));

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowSystemAddress(address(withdrawalQueue));
    }

    function _setUpTrustee() private {
        uint64 roleId = uint64(bytes8(keccak256("TRUSTEE_ROLE")));

        vm.prank(admin);
        authority.grantRole(roleId, trustee, 0);

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = PipelineUSD.mint.selector;
        selectors[1] = PipelineUSD.burn.selector;

        vm.prank(admin);
        authority.setTargetFunctionRole(address(plUsd), selectors, roleId);
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
        authority.setTargetFunctionRole(address(withdrawalQueue), selectors, roleId);
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

    function _setUpQueueManager() private {
        uint64 roleId = uint64(bytes8(keccak256("WITHDRAWAL_QUEUE_MANAGER_ROLE")));

        vm.prank(admin);
        authority.grantRole(roleId, queueManager, 0);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = WithdrawalQueueUpgradeable.increaseClaimable.selector;

        vm.prank(admin);
        authority.setTargetFunctionRole(address(withdrawalQueue), selectors, roleId);
    }
}
