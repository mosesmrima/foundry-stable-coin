//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../script/DeployDSC.s.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {console} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin coin;
    HelperConfig config;
    address weth;
    address wbtc;
    address ethUsdPriceFeed;
    address user = makeAddr("1");
    address liquidator = makeAddr("2");
    uint256 amountToMint = 100 ether;
    uint256 public collateralToCover = 20 ether;
    uint256 amountCollateral = 10 ether;

    function setUp() public {
        vm.deal(user, 100 ether);

        deployer = new DeployDSC();
        (coin, engine, config) = deployer.deploy();
        (ethUsdPriceFeed,, weth, wbtc,) = config.activeNetworkConfig();
        vm.startPrank(user);
        ERC20Mock(weth).mint(user, 20 ether);
        ERC20Mock(weth).approve(address(engine), 20 ether);
        ERC20Mock(weth).approve(liquidator, 20 ether);
        coin.approve(address(engine), 40000 ether);
        vm.stopPrank();

        vm.startPrank(liquidator);
         ERC20Mock(weth).mint(liquidator, 20 ether);
        ERC20Mock(weth).approve(address(engine), 20 ether);
        coin.approve(address(engine), 40000 ether);
        vm.stopPrank();
    }

    address[] public tokenAddress;
    address[] public pricefeeds;

    function testConstructorRevertsWhenArraysHaveDifferentSzes() public {
        tokenAddress.push(weth);
        tokenAddress.push(wbtc);
        pricefeeds.push(ethUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPricefeedsAddressMustBeSameLength.selector);
        new DSCEngine(tokenAddress, pricefeeds, address(coin));
    }

    function testGetUsdValue() public view {
        uint256 ethAmount = 20 ether;
        uint256 expectedsdValue = 40000 ether;
        uint256 actualsdValue = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedsdValue, actualsdValue);
    }

    function testDepositCollateral() public {
        uint256 expectedCollateralValue = engine.getUsdValue(weth, 20 ether);
        vm.startPrank(user);
        engine.depositCollateral(weth, 20 ether);
        uint256 depositedCollateralValue = engine.getAccountCollateralValue(user);
        vm.stopPrank();
        assertEq(depositedCollateralValue, expectedCollateralValue);
    }

    function testDepositsRevertsOnZeroCollateral() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRandomCollateralIsNotSupported() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(makeAddr("1"), 20);
        vm.stopPrank();
    }

    function testDepositCollateralAndMintDsc() public {
        uint256 collateralAmount = 20 ether;
        uint256 expectedCollateralValue = engine.getUsdValue(weth, collateralAmount);

        vm.startPrank(user);
        engine.depositCollateralAndMintDsc(weth, collateralAmount, expectedCollateralValue / 2);
        vm.stopPrank();
        uint256 depositedCollateralValue = engine.getAccountCollateralValue(user);
        uint256 mintedDsc = coin.balanceOf(user);
        assertEq(mintedDsc, expectedCollateralValue / 2);
        assertEq(depositedCollateralValue, expectedCollateralValue);
    }

    function testDepositCollateralAndMintDscRevertsWhenHealtFactorIsBroken() public {
        uint256 collateralAmount = 20 ether;
        uint256 expectedCollateralValue = engine.getUsdValue(weth, collateralAmount);
        uint256 expectedHealthFactor = engine.calculateHealthFactor(25000 ether, expectedCollateralValue);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.depositCollateralAndMintDsc(weth, collateralAmount, 25000 ether);
        vm.stopPrank();
    }

    function testMintDsc() public {
        uint256 collateralAmount = 20 ether;
        uint256 expectedCollateralValue = engine.getUsdValue(weth, collateralAmount);
        vm.startPrank(user);
        engine.depositCollateral(weth, collateralAmount);
        engine.mintDsc(expectedCollateralValue / 2);
        vm.stopPrank();
        uint256 mintedDsc = coin.balanceOf(user);
        assertEq(mintedDsc, expectedCollateralValue / 2);
    }

    function testBurnDsc() public {
        uint256 collateralAmount = 20 ether;
        uint256 expectedCollateralValue = engine.getUsdValue(weth, collateralAmount);
        vm.startPrank(user);
        engine.depositCollateralAndMintDsc(weth, collateralAmount, expectedCollateralValue / 2);
        engine.burnDsc(expectedCollateralValue / 2);
        vm.stopPrank();
        uint256 mintedDsc = coin.balanceOf(user);
        assertEq(mintedDsc, 0);
    }

    function testReemCollateral() public {
        uint256 collateralAmount = 20 ether;
        uint256 expectedCollateralValue = engine.getUsdValue(weth, collateralAmount);
        vm.startPrank(user);
        engine.depositCollateralAndMintDsc(weth, collateralAmount, expectedCollateralValue / 2);
        engine.burnDsc(expectedCollateralValue / 2);
        engine.redeemCollateral(weth, collateralAmount);
        vm.stopPrank();
        uint256 mintedDsc = coin.balanceOf(user);
        assertEq(mintedDsc, 0);
        uint256 collateralValue = engine.getAccountCollateralValue(user);
        assertEq(collateralValue, 0);
    }

    function testRedeemCollateralForDsc() public {
        uint256 collateralAmount = 20 ether;
        uint256 expectedCollateralValue = engine.getUsdValue(weth, collateralAmount);
        vm.startPrank(user);
        engine.depositCollateralAndMintDsc(weth, collateralAmount, expectedCollateralValue / 2);
        engine.redeemCollateralForDsc(weth, expectedCollateralValue / 2, collateralAmount);
        vm.stopPrank();
        uint256 mintedDsc = coin.balanceOf(user);
        assertEq(mintedDsc, 0);
        uint256 collateralValue = engine.getAccountCollateralValue(user);
        assertEq(collateralValue, 0);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 2000 ether;
        uint256 expectedTokenAmount = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedTokenAmount, 1 ether);
    }

    function testGetMintedDscAmount() public {
        uint256 collateralAmount = 20 ether;
        uint256 expectedCollateralValue = engine.getUsdValue(weth, collateralAmount);
        vm.startPrank(user);
        engine.depositCollateralAndMintDsc(weth, collateralAmount, expectedCollateralValue / 2);
        uint256 expectedDscAmount = engine.getMintedDsc();
        vm.stopPrank();

        assertEq(expectedDscAmount, expectedCollateralValue / 2);
    }


    function testUserHealthFactor() public {
        uint256 collateralAmount = 20 ether;
        uint256 expectedCollateralValue = engine.getUsdValue(weth, collateralAmount);
        vm.startPrank(user);
        engine.depositCollateralAndMintDsc(weth, collateralAmount, expectedCollateralValue / 2);
        uint256 expectedHealthFactor = engine.calculateHealthFactor(expectedCollateralValue / 2, expectedCollateralValue);
        uint256 actualHealthFactor = engine.getUserHealthFactor();
        vm.stopPrank();
        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    // function testLiquidate() public {
    //     uint256 collateralAmount = 20 ether;
    //     uint256 expectedCollateralValue = engine.getUsdValue(weth, collateralAmount);
    //     vm.startPrank(user);
    //     engine.depositCollateralAndMintDsc(weth, collateralAmount, expectedCollateralValue / 2);
    //     vm.stopPrank();

    //     int256 ethUsdUpdatedPrice = 18e8;
    //     MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        
    //     engine.liquidate(weth, user, collateralAmount);
    //     vm.startPrank(liquidator);
    //      ERC20Mock(weth).approve(address(engine), collateralAmount);
    //     engine.depositCollateralAndMintDsc(weth, 100*collateralAmount, expectedCollateralValue / 2);
        
    //     vm.stopPrank();
    //     uint256 mintedDsc = coin.balanceOf(user);
    //     assertEq(mintedDsc, 0);
    //     uint256 collateralValue = engine.getAccountCollateralValue(user);
    //     assertEq(collateralValue, 0);
    // }



    modifier liquidated() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = engine.getHealthFactor(user);

        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(engine), collateralToCover);
        engine.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        coin.approve(address(engine), amountToMint);
        engine.liquidate(weth, user, amountToMint); // We are covering their whole debt
        vm.stopPrank();
        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);
        uint256 expectedWeth = engine.getTokenAmountFromUsd(weth, amountToMint )
            + (engine.getTokenAmountFromUsd(weth, amountToMint) / engine.getLiquidationBonus()) + 20 ether;
        uint256 hardCodedExpected = 6_111_111_111_111_111_110 + 20 ether;
        assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, expectedWeth);
    }
}