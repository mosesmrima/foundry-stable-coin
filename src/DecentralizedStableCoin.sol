//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
* @title: DecentralizedStableCoin
* @author: Mrima
* Collateral: exogenous (wETH, BTC)
* Minting: ALogrihimic
* Relative stablity: pegged
* This cntracts is going to be govenerd by DSCEngine. This is just an ERC20 implimnetation of the stablecoin
*/
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__MustBeGreaterThanZero();
    error DecentralizedStableCoin__CannotBunrMoreThanBalance();
    error DecentralizedStableCoin__CannotMintToAddressZero();

    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount < 0) {
            revert DecentralizedStableCoin__MustBeGreaterThanZero();
        }
        if (_amount > balance) {
            revert DecentralizedStableCoin__CannotBunrMoreThanBalance();
        }

        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__CannotMintToAddressZero();
        }

        if (_amount < 0) {
            revert DecentralizedStableCoin__MustBeGreaterThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
