//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../script/DeployDSC.s.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin coin;
    HelperConfig config;
    address weth;
    address wbtc;
    address ethUsdPriceFeed;
    address user = makeAddr("1");

    function setUp() public {
        vm.deal(user, 100 ether);

        deployer = new DeployDSC();
        (coin, engine, config) = deployer.deploy();
        (ethUsdPriceFeed,, weth,wbtc,) = config.activeNetworkConfig();
        vm.startPrank(user);
        ERC20Mock(weth).mint(user, 20);
        ERC20Mock(weth).approve(address(engine), 20);
        vm.stopPrank();
    }

    address [] public tokenAddress;
    address [] public pricefeeds;
    function testConstructorRevertsWhenArraysHaveDifferentSzes() public {
        tokenAddress.push(weth);
        tokenAddress.push(wbtc);
        pricefeeds.push(ethUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPricefeedsAddressMustBesameLength.selector);
        new DSCEngine(tokenAddress, pricefeeds, address(coin));
    }
    function testGetUsdValue() public view {
        uint256 ethAmount = 20 ether;
        uint256 expectedsdValue = 40000 ether;
        uint256 actualsdValue = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedsdValue, actualsdValue);
    }

    function testDepositCollateral() public {
        uint256 expectedCollateralValue = engine.getUsdValue(weth, 20);
        vm.startPrank(user);
        engine.depositCollateral(weth, 20);
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
        uint256 expectedCollateralValue = engine.getUsdValue(weth, 20);
        uint256 expectedDscValue = 20;
        vm.startPrank(user);
        engine.depositCollateral(weth, 20);
        engine.mintDsc(20);
        uint256 depositedCollateralValue = engine.getAccountCollateralValue(user);
        uint256 depositedDscValue = engine.getMIntedDsc();
        vm.stopPrank();
        assertEq(depositedCollateralValue, expectedCollateralValue);
        assertEq(depositedDscValue, expectedDscValue);
    }
}
