// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.34;

import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";

import {MinterUpgradeable} from "./minter/MinterUpgradeable.sol";
import {YieldVesting} from "./minter/YieldVesting.sol";

contract PipelineMinterReader {
    using SlotDerivation for bytes32;

    uint256 private constant PL_USD = 0;
    uint256 private constant STAKED_PL_USD = 1;
    uint256 private constant LOAN_REGISTRY = 2;
    uint256 private constant POCKET = 3;
    uint256 private constant USDC = 4;
    uint256 private constant TREASURY = 5;
    uint256 private constant FACTORY = 6;
    uint256 private constant CUSTODIANS = 7;
    uint256 private constant BANK_CASH = 8;
    uint256 private constant IN_FLIGHT = 9;
    uint256 private constant UNABSORBED_TOTAL = 10;
    uint256 private constant NEXT_WIRE_IN_ID = 11;
    uint256 private constant NEXT_WIRE_OUT_ID = 12;
    uint256 private constant NEXT_RAMP_ID = 13;
    uint256 private constant NEXT_CASH_ENTRY_ID = 14;
    uint256 private constant WIRES_IN = 15;
    uint256 private constant WIRES_OUT = 16;
    uint256 private constant RAMPS = 17;
    uint256 private constant DISBURSEMENTS = 18;
    uint256 private constant REPAYMENTS = 19;
    uint256 private constant REF_HASHES_SEEN = 20;
    uint256 private constant YIELD_SCHEDULE = 21;

    MinterUpgradeable public immutable minter;
    bytes32 private immutable _minterStorage;

    constructor(address _minter) {
        minter = MinterUpgradeable(_minter);
        _minterStorage = SlotDerivation.erc7201Slot("pipeline.storage.Minter");
    }

    function addressesConfig() external view returns (MinterUpgradeable.AddressesConfig memory) {
        return MinterUpgradeable.AddressesConfig({
            plUsd: _address(PL_USD),
            stakedPlUsd: _address(STAKED_PL_USD),
            loanRegistry: _address(LOAN_REGISTRY),
            pocket: _address(POCKET),
            usdc: _address(USDC),
            treasury: _address(TREASURY),
            factory: _address(FACTORY)
        });
    }

    function custodians() external view returns (address[] memory result) {
        bytes32 slot = _field(CUSTODIANS);
        bytes32 data = slot.deriveArray();

        result = new address[](_read(slot));
        for (uint256 i; i < result.length; ++i) {
            result[i] = address(uint160(_read(data.offset(i))));
        }
    }

    function bankCash() external view returns (uint256) {
        return _read(_field(BANK_CASH));
    }

    function inFlight() external view returns (uint256) {
        return _read(_field(IN_FLIGHT));
    }

    function unabsorbedTotal() external view returns (uint256) {
        return _read(_field(UNABSORBED_TOTAL));
    }

    function wireIn(uint256 id) external view returns (MinterUpgradeable.WireIn memory) {
        if (id >= _read(_field(NEXT_WIRE_IN_ID))) revert MinterUpgradeable.MinterNonExistentWireIn();

        bytes32 slot = _field(WIRES_IN).deriveMapping(id);
        return MinterUpgradeable.WireIn({
            status: MinterUpgradeable.WireInStatus(uint8(_read(slot))), amount: _read(slot.offset(1))
        });
    }

    function wireOut(uint256 id) external view returns (MinterUpgradeable.WireOut memory) {
        if (id >= _read(_field(NEXT_WIRE_OUT_ID))) revert MinterUpgradeable.MinterNonExistentWireOut();

        bytes32 slot = _field(WIRES_OUT).deriveMapping(id);
        uint256 word = _read(slot);
        return MinterUpgradeable.WireOut({
            lp: address(uint160(word)),
            status: MinterUpgradeable.WireOutStatus(uint8(word >> 160)),
            amount: _read(slot.offset(1))
        });
    }

    function ramp(uint256 id) external view returns (MinterUpgradeable.Ramp memory) {
        if (id >= _read(_field(NEXT_RAMP_ID))) revert MinterUpgradeable.MinterNonExistentRamp();

        bytes32 slot = _field(RAMPS).deriveMapping(id);
        uint256 word = _read(slot);
        return MinterUpgradeable.Ramp({
            direction: MinterUpgradeable.RampDirection(uint8(word)),
            closed: uint8(word >> 8) != 0,
            amount: _read(slot.offset(1))
        });
    }

    function disbursement(uint256 entryId) external view returns (MinterUpgradeable.Disbursement memory entry) {
        if (entryId >= _read(_field(NEXT_CASH_ENTRY_ID))) revert MinterUpgradeable.MinterNonExistentCashEntry();

        bytes32 slot = _field(DISBURSEMENTS).deriveMapping(entryId);
        entry = MinterUpgradeable.Disbursement({
            loanId: _read(slot), amount: _read(slot.offset(1)), reversed: uint8(_read(slot.offset(2))) != 0
        });
        if (entry.amount == 0) revert MinterUpgradeable.MinterWrongEntry();
    }

    function repayment(uint256 loanId, uint256 repaymentId) external view returns (MinterUpgradeable.Repayment memory) {
        bytes32 slot = _field(REPAYMENTS).deriveMapping(loanId).deriveMapping(repaymentId);
        uint256 word = _read(slot.offset(3));
        return MinterUpgradeable.Repayment({
            feeShares: _read(slot),
            fees: _read(slot.offset(1)),
            released: _read(slot.offset(2)),
            carvedOut: uint8(word) != 0,
            yieldEpoch: uint64(word >> 8)
        });
    }

    function refHashSeen(bytes32 refHash) external view returns (bool) {
        return _read(_field(REF_HASHES_SEEN).deriveMapping(refHash)) != 0;
    }

    function yieldSchedule() external view returns (YieldVesting.Schedule memory schedule) {
        (schedule,) = YieldVesting.current(_schedule(), block.timestamp);
    }

    function releasableYield() external view returns (uint256 due) {
        (, due) = YieldVesting.current(_schedule(), block.timestamp);
    }

    function pendingYield() external view returns (uint256) {
        return YieldVesting.pending(_schedule(), block.timestamp);
    }

    function _schedule() private view returns (YieldVesting.Schedule memory) {
        bytes32 slot = _field(YIELD_SCHEDULE);
        return YieldVesting.Schedule({
            epoch: _read(slot),
            accruing: _read(slot.offset(1)),
            vesting: _read(slot.offset(2)),
            released: _read(slot.offset(3))
        });
    }

    function _address(uint256 field) private view returns (address) {
        return address(uint160(_read(_field(field))));
    }

    function _field(uint256 field) private view returns (bytes32) {
        return _minterStorage.offset(field);
    }

    function _read(bytes32 slot) private view returns (uint256) {
        return uint256(minter.extsload(slot));
    }
}
