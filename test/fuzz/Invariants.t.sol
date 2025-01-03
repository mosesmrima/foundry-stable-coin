// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {console} from "forge-std/Script.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Invariants is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin coin;
    HelperConfig config;
    address weth;
    address wbtc;
    address ethUsdPriceFeed;
    address wbtcPriceFeed;

    function setUp() external {
        deployer = new DeployDSC();
        (coin, engine, config) = deployer.deploy();
        (ethUsdPriceFeed, wbtcPriceFeed, weth, wbtc,) = config.activeNetworkConfig();

        targetContract(address(engine));
    }

    function invariant_ContractMustHaveMoreCollateralThanDebt() public view {
        uint256 dscSupply = coin.totalSupply();
        uint256 wethSuply = IERC20(weth).balanceOf(address(engine));
        uint256 wbtcSuply = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getUsdValue(weth, wethSuply);
        uint256 wbtcValue = engine.getUsdValue(wbtc, wbtcSuply);

        assert(wethValue + wbtcValue >= dscSupply);
    }
}
