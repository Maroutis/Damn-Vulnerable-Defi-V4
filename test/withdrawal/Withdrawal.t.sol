// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {L1Gateway} from "../../src/withdrawal/L1Gateway.sol";
import {L1Forwarder} from "../../src/withdrawal/L1Forwarder.sol";
import {L2MessageStore} from "../../src/withdrawal/L2MessageStore.sol";
import {L2Handler} from "../../src/withdrawal/L2Handler.sol";
import {L2MessageStore} from "../../src/withdrawal/L2MessageStore.sol";
import {TokenBridge} from "../../src/withdrawal/TokenBridge.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

contract WithdrawalChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");

    // Mock addresses of the bridge's L2 components
    address l2MessageStore = makeAddr("l2MessageStore");
    address l2TokenBridge = makeAddr("l2TokenBridge");
    address l2Handler = makeAddr("l2Handler");

    uint256 constant START_TIMESTAMP = 1718786915;
    uint256 constant INITIAL_BRIDGE_TOKEN_AMOUNT = 1_000_000e18;
    uint256 constant WITHDRAWALS_AMOUNT = 4;
    bytes32 constant WITHDRAWALS_ROOT = 0x4e0f53ae5c8d5bc5fd1a522b9f37edfd782d6f4c7d8e0df1391534c081233d9e;

    TokenBridge l1TokenBridge;
    DamnValuableToken token;
    L1Forwarder l1Forwarder;
    L1Gateway l1Gateway;
    L2MessageStore l2MessageStoreInstance;
    L2Handler l2HandlerInstance;

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
        startHoax(deployer);

        // Start at some realistic timestamp
        vm.warp(START_TIMESTAMP);

        // Deploy token
        token = new DamnValuableToken();

        // Deploy and setup infra for message passing
        l1Gateway = new L1Gateway();
        l1Forwarder = new L1Forwarder(l1Gateway);
        l1Forwarder.setL2Handler(address(l2Handler));

        // Deploy token bridge on L1
        l1TokenBridge = new TokenBridge(token, l1Forwarder, l2TokenBridge);

        // Set bridge's token balance, manually updating the `totalDeposits` value (at slot 0)
        token.transfer(address(l1TokenBridge), INITIAL_BRIDGE_TOKEN_AMOUNT);
        vm.store(address(l1TokenBridge), 0, bytes32(INITIAL_BRIDGE_TOKEN_AMOUNT));

        // Set withdrawals root in L1 gateway
        l1Gateway.setRoot(WITHDRAWALS_ROOT);

        // Grant player the operator role
        l1Gateway.grantRoles(player, l1Gateway.OPERATOR_ROLE());

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(l1Forwarder.owner(), deployer);
        assertEq(address(l1Forwarder.gateway()), address(l1Gateway));

        assertEq(l1Gateway.owner(), deployer);
        assertEq(l1Gateway.rolesOf(player), l1Gateway.OPERATOR_ROLE());
        assertEq(l1Gateway.DELAY(), 7 days);
        assertEq(l1Gateway.root(), WITHDRAWALS_ROOT);

        assertEq(token.balanceOf(address(l1TokenBridge)), INITIAL_BRIDGE_TOKEN_AMOUNT);
        assertEq(l1TokenBridge.totalDeposits(), INITIAL_BRIDGE_TOKEN_AMOUNT);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_withdrawal() public checkSolvedByPlayer {

        // This level is pretty straighforward. The only thing that took me some time to figure out is the fact that the event's data encoding and the encoding of the calldata sent by users to execute a tx is different. For this to work we have to encode the messages in the exact same way as how it was when the users sent their tx. We can't rely on the events by plugging the values directly.

        // eaebef7f15fdaa66ecd4533eefea23a183ced29967ea67bc4219b0f1f8b0d3ba
        // 0000000000000000000000000000000000000000000000000000000066729b63
        // 0000000000000000000000000000000000000000000000000000000000000060
        // 0000000000000000000000000000000000000000000000000000000000000104
        // 01210a38
        // 0000000000000000000000000000000000000000000000000000000000000000
        // 000000000000000000000000328809bc894f92807417d2dad6b7c998c1afdac6
        // 0000000000000000000000009c52b2c4a89e2be37972d18da937cbad8aa8bd50
        // 0000000000000000000000000000000000000000000000000000000000000080
        // 0000000000000000000000000000000000000000000000000000000000000044
        // 81191e51
        // 000000000000000000000000328809bc894f92807417d2dad6b7c998c1afdac6
        // 0000000000000000000000000000000000000000000000008ac7230489e80000
        // 0000000000000000000000000000000000000000000000000000000000000000
        // 000000000000000000000000000000000000000000000000

        uint256 nonce;
        address l2Sender;
        address target;
        uint256 timestamp;
        bytes memory message;
        bytes32[] memory proof;
        address receiver;
        uint256 amount;
        bytes memory executeTokenWithdrawalCall;
        address msgSender;
        address targetContractInforwardMessageCall;

        nonce = uint256(0x0000000000000000000000000000000000000000000000000000000000000000);
        l2Sender = address(l2Handler);
        target = address(l1Forwarder);
        timestamp = uint256(0x0000000000000000000000000000000000000000000000000000000066729b63);
        receiver = address(0x000000000000000000000000328809bc894f92807417d2dad6b7c998c1afdac6);
        amount = uint256(0x0000000000000000000000000000000000000000000000008ac7230489e80000);
        console.log(amount);
        executeTokenWithdrawalCall = abi.encodeWithSelector(l1TokenBridge.executeTokenWithdrawal.selector, receiver, amount);
        msgSender = address(0x000000000000000000000000328809bc894f92807417d2dad6b7c998c1afdac6);
        targetContractInforwardMessageCall = address(0x0000000000000000000000009c52b2c4a89e2be37972d18da937cbad8aa8bd50);
        message = abi.encodeCall(L1Forwarder.forwardMessage, (nonce, msgSender, targetContractInforwardMessageCall, executeTokenWithdrawalCall));

        vm.warp(timestamp + l1Gateway.DELAY());

        // 01210a38
        // 0000000000000000000000000000000000000000000000000000000000000000
        // 000000000000000000000000328809bc894f92807417d2dad6b7c998c1afdac6
        // 0000000000000000000000009c52b2c4a89e2be37972d18da937cbad8aa8bd50
        // 0000000000000000000000000000000000000000000000000000000000000080
        // 0000000000000000000000000000000000000000000000000000000000000044
        // 81191e51
        // 000000000000000000000000328809bc894f92807417d2dad6b7c998c1afdac6
        // 0000000000000000000000000000000000000000000000008ac7230489e80000
        // 00000000000000000000000000000000000000000000000000000000

        // 01210a38
        // 0000000000000000000000000000000000000000000000000000000000000000
        // 000000000000000000000000328809bc894f92807417d2dad6b7c998c1afdac6
        // 0000000000000000000000009c52b2c4a89e2be37972d18da937cbad8aa8bd50
        // 0000000000000000000000000000000000000000000000000000000000000080
        // 0000000000000000000000000000000000000000000000000000000000000044
        // 81191e51
        // 000000000000000000000000328809bc894f92807417d2dad6b7c998c1afdac6
        // 0000000000000000000000000000000000000000000000008ac7230489e80000
        // 0000000000000000000000000000000000000000000000000000000000000000
        // 000000000000000000000000000000000000000000000000

        l1Gateway.finalizeWithdrawal(nonce, l2Sender, target, timestamp, message, proof);

        // 01210a38
        // 0000000000000000000000000000000000000000000000000000000000000001
        // 0000000000000000000000001d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e
        // 0000000000000000000000009c52b2c4a89e2be37972d18da937cbad8aa8bd50
        // 0000000000000000000000000000000000000000000000000000000000000080
        // 0000000000000000000000000000000000000000000000000000000000000044
        // 81191e51
        // 0000000000000000000000001d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e
        // 0000000000000000000000000000000000000000000000008ac7230489e80000
        // 0000000000000000000000000000000000000000000000000000000000000000
        // 000000000000000000000000000000000000000000000000


        nonce = 0x0000000000000000000000000000000000000000000000000000000000000001;
        l2Sender = address(0x00000000000000000000000087EAD3e78Ef9E26de92083b75a3b037aC2883E16);
        target = address(0x000000000000000000000000fF2Bd636B9Fc89645C2D336aeaDE2E4AbaFe1eA5);
        timestamp = uint256(0x00000000000000000000000000000000000000000000000000000000066729b95);

        receiver = address(0x0000000000000000000000001d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e);
        amount = uint256(0x0000000000000000000000000000000000000000000000008ac7230489e80000);
        executeTokenWithdrawalCall = abi.encodeWithSelector(l1TokenBridge.executeTokenWithdrawal.selector, receiver, amount);

        msgSender = address(0x0000000000000000000000001d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e);
        targetContractInforwardMessageCall = address(0x0000000000000000000000009c52b2c4a89e2be37972d18da937cbad8aa8bd50);
        message = abi.encodeCall(L1Forwarder.forwardMessage, (nonce, msgSender, targetContractInforwardMessageCall, executeTokenWithdrawalCall));

        vm.warp(timestamp + l1Gateway.DELAY());
        l1Gateway.finalizeWithdrawal(nonce, l2Sender, target, timestamp, message, proof);

        // If we try to execute the third transaction. We notice that the amount that the user is trying to withraw is huge = 999000000000000000000000 or 999000 ether. So we will have to cancel his tx. In order to do that, the easiest way is to make the call to tokenBridge fail which would still validate the tx while it has no effect. To do that we can just send a tx to tokenBridge via the gateway to withdraw just enough tokens for the following to fail. We can do that sicne we have special access "OPERATOR_ROLE". Let's do it !
        // Withraw some tokens from TokenBridge to ourselves
        nonce = 0x0000000000000000000000000000000000000000000000000000000000000004;
        l2Sender = address(0x00000000000000000000000087EAD3e78Ef9E26de92083b75a3b037aC2883E16);
        target = address(0x000000000000000000000000fF2Bd636B9Fc89645C2D336aeaDE2E4AbaFe1eA5);
        // timestamp = uint256(0x0000000000000000000000000000000000000000000000000000000066729bea); Use the same timestamp as the tx before

        receiver = player;
        uint256 scammerAmount = uint256(0x00000000000000000000000000000000000000000000d38be6051f27c2600000);
        amount = token.balanceOf(address(l1TokenBridge)) - scammerAmount + 1;
        executeTokenWithdrawalCall = abi.encodeWithSelector(l1TokenBridge.executeTokenWithdrawal.selector, receiver, amount); // Withdraw just the minimal amount that would fail the next tx.

        msgSender = player;
        targetContractInforwardMessageCall = address(0x0000000000000000000000009c52b2c4a89e2be37972d18da937cbad8aa8bd50);
        message = abi.encodeCall(L1Forwarder.forwardMessage, (nonce, msgSender, targetContractInforwardMessageCall, executeTokenWithdrawalCall));

        // vm.warp(timestamp + l1Gateway.DELAY()); // No need to warp
        l1Gateway.finalizeWithdrawal(nonce, l2Sender, target, timestamp, message, proof);

        // Now we finalize the next one :

        // 01210a38
        // 0000000000000000000000000000000000000000000000000000000000000002
        // 000000000000000000000000ea475d60c118d7058bef4bdd9c32ba51139a74e0
        // 0000000000000000000000009c52b2c4a89e2be37972d18da937cbad8aa8bd50
        // 0000000000000000000000000000000000000000000000000000000000000080
        // 0000000000000000000000000000000000000000000000000000000000000044
        // 81191e51
        // 000000000000000000000000ea475d60c118d7058bef4bdd9c32ba51139a74e0
        // 00000000000000000000000000000000000000000000d38be6051f27c2600000
        // 0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

        nonce = 0x0000000000000000000000000000000000000000000000000000000000000002;
        l2Sender = address(0x00000000000000000000000087EAD3e78Ef9E26de92083b75a3b037aC2883E16);
        target = address(0x000000000000000000000000fF2Bd636B9Fc89645C2D336aeaDE2E4AbaFe1eA5);
        timestamp = uint256(0x0000000000000000000000000000000000000000000000000000000066729bea);

        receiver = address(0x000000000000000000000000ea475d60c118d7058bef4bdd9c32ba51139a74e0);
        amount = uint256(0x00000000000000000000000000000000000000000000d38be6051f27c2600000);
        executeTokenWithdrawalCall = abi.encodeWithSelector(l1TokenBridge.executeTokenWithdrawal.selector, receiver, amount);

        msgSender = address(0x000000000000000000000000ea475d60c118d7058bef4bdd9c32ba51139a74e0);
        targetContractInforwardMessageCall = address(0x0000000000000000000000009c52b2c4a89e2be37972d18da937cbad8aa8bd50);
        message = abi.encodeCall(L1Forwarder.forwardMessage, (nonce, msgSender, targetContractInforwardMessageCall, executeTokenWithdrawalCall));

        vm.warp(timestamp + l1Gateway.DELAY());
        l1Gateway.finalizeWithdrawal(nonce, l2Sender, target, timestamp, message, proof);
        // This tx should have no effect.

        // Now that we have finalized to scammer tx, we send the tokens back to tokenBridge
        token.transfer(address(l1TokenBridge), token.balanceOf(player));

        // Finalize the rest

        // 01210a38
        // 0000000000000000000000000000000000000000000000000000000000000003
        // 000000000000000000000000671d2ba5bf3c160a568aae17de26b51390d6bd5b
        // 0000000000000000000000009c52b2c4a89e2be37972d18da937cbad8aa8bd50
        // 0000000000000000000000000000000000000000000000000000000000000080
        // 0000000000000000000000000000000000000000000000000000000000000044
        // 81191e51
        // 000000000000000000000000671d2ba5bf3c160a568aae17de26b51390d6bd5b
        // 0000000000000000000000000000000000000000000000008ac7230489e80000
        // 0000000000000000000000000000000000000000000000000000000000000000
        // 000000000000000000000000000000000000000000000000

        nonce = 0x0000000000000000000000000000000000000000000000000000000000000003;
        l2Sender = address(0x00000000000000000000000087EAD3e78Ef9E26de92083b75a3b037aC2883E16);
        target = address(0x000000000000000000000000fF2Bd636B9Fc89645C2D336aeaDE2E4AbaFe1eA5);
        timestamp = uint256(0x0000000000000000000000000000000000000000000000000000000066729c37);
        
        receiver = address(0x000000000000000000000000671d2ba5bf3c160a568aae17de26b51390d6bd5b);
        amount = uint256(0x0000000000000000000000000000000000000000000000008ac7230489e80000);
        executeTokenWithdrawalCall = abi.encodeWithSelector(l1TokenBridge.executeTokenWithdrawal.selector, receiver, amount);

        msgSender = address(0x000000000000000000000000671d2ba5bf3c160a568aae17de26b51390d6bd5b);
        targetContractInforwardMessageCall = address(0x0000000000000000000000009c52b2c4a89e2be37972d18da937cbad8aa8bd50);
        message = abi.encodeCall(L1Forwarder.forwardMessage, (nonce, msgSender, targetContractInforwardMessageCall, executeTokenWithdrawalCall));

        vm.warp(timestamp + l1Gateway.DELAY());
        l1Gateway.finalizeWithdrawal(nonce, l2Sender, target, timestamp, message, proof);
        
    }

    function testHandler() external {
        l2MessageStoreInstance = new L2MessageStore();
        l2HandlerInstance = new L2Handler(l2MessageStoreInstance, l1Forwarder);
        console.log(address(l2HandlerInstance));
        console.log("address(l2Handler);", address(l2Handler));
        vm.startPrank(address(0x000000000000000000000000328809bc894f92807417d2dad6b7c998c1afdac6));
    
        console.log(uint256(0x0000000000000000000000000000000000000000000000008ac7230489e80000));
        l2HandlerInstance.sendMessage(address(0x0000000000000000000000009c52b2c4a89e2be37972d18da937cbad8aa8bd50), abi.encodeWithSelector(l1TokenBridge.executeTokenWithdrawal.selector, address(0x000000000000000000000000328809bc894f92807417d2dad6b7c998c1afdac6), uint256(0x0000000000000000000000000000000000000000000000008ac7230489e80000)));
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Token bridge still holds most tokens
        assertLt(token.balanceOf(address(l1TokenBridge)), INITIAL_BRIDGE_TOKEN_AMOUNT);
        assertGt(token.balanceOf(address(l1TokenBridge)), INITIAL_BRIDGE_TOKEN_AMOUNT * 99e18 / 100e18);

        // Player doesn't have tokens
        assertEq(token.balanceOf(player), 0);

        // All withdrawals in the given set (including the suspicious one) must have been marked as processed and finalized in the L1 gateway
        assertGe(l1Gateway.counter(), WITHDRAWALS_AMOUNT, "Not enough finalized withdrawals");
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"eaebef7f15fdaa66ecd4533eefea23a183ced29967ea67bc4219b0f1f8b0d3ba"),
            "First withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"0b130175aeb6130c81839d7ad4f580cd18931caf177793cd3bab95b8cbb8de60"),
            "Second withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"baee8dea6b24d327bc9fcd7ce867990427b9d6f48a92f4b331514ea688909015"),
            "Third withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"9a8dbccb6171dc54bfcff6471f4194716688619305b6ededc54108ec35b39b09"),
            "Fourth withdrawal not finalized"
        );
    }
}
