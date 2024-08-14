// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {console, Test} from "forge-std/Test.sol";
import {Challenge} from "../../src/hidden/hidden.sol";

contract hiddenTest is Test{
    Challenge public challengeContractInstance;

    function setUp() public {
        challengeContractInstance = new Challenge();
    }

    function testsolve(uint8 value) external isSolved {

        challengeContractInstance.hidden(value);
        console.log(challengeContractInstance.sum());
    }

    function testNeverEqualTo10(uint8 value) external {
        challengeContractInstance.hidden(value);

        assertFalse(challengeContractInstance.sum() == 10);
    }

    modifier isSolved() {
        _;
        if (challengeContractInstance.sum() == 10) {
            console.log("flag{dummy_flag_here}");
        } else {
            console.log("nope, that's not it my bro!");
        }
    }
}
