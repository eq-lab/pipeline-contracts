// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessManaged} from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {PipelineUSD} from "../src/PipelineUSD.sol";
import {StakedPipelineUSD} from "../src/StakedPipelineUSD.sol";
import {WhitelistRegistry} from "../src/WhitelistRegistry.sol";
import {WhitelistAccessedUpgradeable} from "../src/whitelist/WhitelistAccessedUpgradeable.sol";
import {WhitelistAccessUpgradeable} from "../src/whitelist/WhitelistAccessUpgradeable.sol";

contract CounterTest is Test {
    AccessManager public authority;
    WhitelistRegistry public whitelistRegistry;
    PipelineUSD public plUsd;
    StakedPipelineUSD public sPlUsd;

    address public admin = makeAddr("admin");
    address public trustee = makeAddr("trustee");
    address public upgrader = makeAddr("upgrader");
    address public pauser = makeAddr("pauser");
    address public whitelistAdmin = makeAddr("whitelistAdmin");

    function setUp() public {
        _setUpAuthority();
        _setUpWhitelistRegistry();
        _setUpPlUsd();
        _setUpSPlUsd();

        _setUpTrustee();
        _setUpPauser();
        _setUpUpgrader();
        _setUpWhitelistAdmin();
    }

    function test_setUp() public view {
        assertEq(plUsd.authority(), address(authority));
        assertEq(sPlUsd.authority(), address(authority));
        assertEq(whitelistRegistry.authority(), address(authority));

        assertEq(sPlUsd.asset(), address(plUsd));
    }

    function testFuzz_transfersWhitelist(address noAccess) public {
        vm.assume(noAccess != address(0));
        vm.assume(!whitelistRegistry.isAllowed(noAccess));

        address withAccess = makeAddr("withAccess");

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowUser(withAccess, type(uint256).max);

        vm.prank(noAccess);
        vm.expectRevert(abi.encodeWithSelector(WhitelistAccessedUpgradeable.NoAccess.selector, noAccess));
        plUsd.transfer(withAccess, 1);

        vm.prank(withAccess);
        vm.expectRevert(abi.encodeWithSelector(WhitelistAccessedUpgradeable.NoAccess.selector, noAccess));
        plUsd.transfer(noAccess, 1);
    }

    function testFuzz_trusteeAccess(address caller) public {
        vm.assume(caller != trustee);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        plUsd.mint(caller, 1);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        plUsd.burn(caller, 1);
    }

    function testFuzz_pauserAccess(address caller) public {
        vm.assume(caller != pauser);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        plUsd.pause();

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        plUsd.unpause();
    }

    function testFuzz_upgraderAccess(address caller) public {
        vm.assume(caller != upgrader);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        UUPSUpgradeable(address(plUsd)).upgradeToAndCall(address(plUsd), "");

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        UUPSUpgradeable(address(sPlUsd)).upgradeToAndCall(address(sPlUsd), "");

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        UUPSUpgradeable(address(whitelistRegistry)).upgradeToAndCall(address(whitelistRegistry), "");
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
}
