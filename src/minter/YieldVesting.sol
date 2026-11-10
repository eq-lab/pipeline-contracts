// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

library YieldVesting {
    uint256 internal constant EPOCH = 30 days;

    struct Schedule {
        uint256 epoch;
        uint256 accruing;
        uint256 vesting;
        uint256 released;
    }

    function current(Schedule memory schedule, uint256 timestamp) internal pure returns (Schedule memory, uint256 due) {
        uint256 epoch = timestamp / EPOCH;
        if (epoch > schedule.epoch) {
            due = schedule.vesting - schedule.released;
            if (epoch == schedule.epoch + 1) {
                schedule.vesting = schedule.accruing;
            } else {
                due += schedule.accruing;
                schedule.vesting = 0;
            }
            schedule.accruing = 0;
            schedule.released = 0;
            schedule.epoch = epoch;
        }
        uint256 released = vested(schedule.vesting, timestamp);
        due += released - schedule.released;
        schedule.released = released;
        return (schedule, due);
    }

    function pending(Schedule memory schedule, uint256 timestamp) internal pure returns (uint256) {
        uint256 due;
        (schedule, due) = current(schedule, timestamp);
        return schedule.accruing + schedule.vesting - schedule.released + due;
    }

    function vested(uint256 vesting, uint256 timestamp) internal pure returns (uint256) {
        return vesting * (timestamp % EPOCH) / EPOCH;
    }
}
