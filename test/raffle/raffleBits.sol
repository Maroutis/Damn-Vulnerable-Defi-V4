// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), _owner);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract Raffle is Ownable {
    mapping(address => bytes32) public participations;

    function participate(uint128 amountPaid, uint32 ticketCount) public {
        bytes32 participation = bytes32(uint256(amountPaid | (ticketCount << 128)));
        participations[msg.sender] = participation;
    }

    // Function to mark a participation as refunded
    function markRefunded() public onlyOwner {
        bytes32 participation = participations[msg.sender];
        participations[msg.sender] = bytes32(participation | bytes32(uint256((1 << 160))));
    }

    // Function to check if a player has been refunded
    function isRefunded() public view returns (bool) {
        bytes32 participation = participations[msg.sender];
        return (((uint256(participation) >> 160) | 1) == 1);
    }
}
