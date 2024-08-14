// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

contract Challenge {
    uint256 public sum;

    function hidden(uint8 a) external returns (uint256 output) {
        output = 16777215 + a; // 2**24 - 1
        sum = output;
    }
}
