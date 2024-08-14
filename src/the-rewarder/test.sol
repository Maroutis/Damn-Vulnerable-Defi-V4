
// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {Merkle} from "murky/Merkle.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {TheRewarderDistributor, IERC20, Distribution, Claim} from "../../src/the-rewarder/TheRewarderDistributor.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

contract Challenge is Test {
    decodeEncode de;
    function setUp() public {
        de = new decodeEncode();
    }

    function testMint() public {
        de.decode(de.mint(5));
    }
}

contract decodeEncode {
enum MessageType {
    BURN,
    MINT
}

mapping(bytes32 => uint256) public continueFrom;

function mint(uint256 tokenId) external returns(bytes memory){
    bytes memory payload = abi.encode(msg.sender, tokenId);
    payload = abi.encodePacked(MessageType.MINT, payload);
    // Do some stuff, then decode is called on the other chain
    return payload;
}

function decode(bytes memory payload) external {
    bytes memory payloadWithoutMessage;
    console.logBytes(payload);
    console.log("******************************");
    uint256 length1;
    uint256 length2;
    assembly {
        payloadWithoutMessage := add(payload,1)
        length1 := mload(payload)
        length2 := mload(payloadWithoutMessage)
    }
    console.log(length1);
    console.log(length2);
    MessageType messageType = MessageType(uint8(payload[0]));
    if(messageType != MessageType.MINT){
        return;
    }
    uint256 lastIndex = 5;
    // Do some stuff in a loop and if the loop is not done, it will store it for later retry
    bytes32 hashedPayload = keccak256(payloadWithoutMessage);
    continueFrom[hashedPayload] = lastIndex;
}

function retry(bytes memory payload) external {
    bytes32 hashedPayload = keccak256(payload);
    require(continueFrom[hashedPayload] != 0, "no credits stored");

    // Continue the loop from lastIndex like in decode(), if cannot finish, it will store it again
}
}