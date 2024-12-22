//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    DSCEngine dscEngine;
    DecentralizedStableCoin dscCoin;
    HelperConfig config;
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    address wethUsdPriceFeed;
    address wbtcPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;

    constructor() {
        config = new HelperConfig();
        (wethUsdPriceFeed, wbtcPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];

        priceFeedAddresses = [wethUsdPriceFeed, wbtcPriceFeed];
    }

    function deploy() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        vm.startBroadcast(deployerKey);
        dscCoin = new DecentralizedStableCoin();
        dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dscCoin));
        dscCoin.transferOwnership(address(dscEngine));
        vm.stopBroadcast();
        return (dscCoin, dscEngine, config);
    }
}
