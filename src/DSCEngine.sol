//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
/*
 * @title: DCEngine
 * @author: Mrima
 * This engine is designed to maintain 1usd to 1 token eg. I has the followinfg properties:
 *       1. Relative Stabilitiy: pegged to USD
 *       2. Stability Mechanism(Minting): Algorithimic
 *       3. Collateral: Exogenous(ETH and BTC)
 * It is simlar to DAI, if DAI had no fees, no governance and wasonly backed by wETH and wBTC
 * @notice: ths conract handles all the ogic and functins, it is loosly based on DAI.
 */

contract DSCEngine is ReentrancyGuard {
    //////////////////
    /// Errors //////
    /////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressAndPricefeedsAddressMustBesameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BReaksHealthFactor(uint256 _userHealthFactor);
    error DSCEngine__MintFailed(address _user);
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    ///////////////////////
    /// State Variables ///
    //////////////////////

    uint256 private constant PRICEFEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATATION_PRECISION = 100;
    uint256 private constant LIQUIDATOR_BONUS = 10;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    mapping(address token => address pricefeed) private s_pricefeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DscMinted;
    address[] private s_collateralTokens;
    DecentralizedStableCoin private immutable i_dsc;

    //////////////////
    /// Events //////
    /////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    //////////////////
    /// Modifiers ///
    /////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _addressToken) {
        if (s_pricefeeds[_addressToken] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    //////////////////
    /// Functionss ///
    /////////////////
    constructor(address[] memory _tokenAddresses, address[] memory _pricefeedsAddresses, address _dscAddress) {
        if (_tokenAddresses.length != _pricefeedsAddresses.length) {
            revert DSCEngine__TokenAddressAndPricefeedsAddressMustBesameLength();
        }

        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_pricefeeds[_tokenAddresses[i]] = _pricefeedsAddresses[i];
            s_collateralTokens.push(_tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(_dscAddress);
    }

    /*
    * @notice follows CEI pattern
     * @param collateralAddress: address of token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     */
    function depositCollateral(address _collateralAddress, uint256 _amountCollateral)
        public
        moreThanZero(_amountCollateral)
        isAllowedToken(_collateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][_collateralAddress] += _amountCollateral;
        emit CollateralDeposited(msg.sender, _collateralAddress, _amountCollateral);
        bool success = IERC20(_collateralAddress).transferFrom(msg.sender, address(this), _amountCollateral);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /*
    * @notice they must have more collateral than the minimum threshold
    * @param _amount the amount of descetralized stable coint to mint
    */
    function mintDsc(uint256 _amount) public moreThanZero(_amount) {
        s_DscMinted[msg.sender] = _amount;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, _amount);

        if (!minted) {
            revert DSCEngine__MintFailed(msg.sender);
        }
    }

    /*
    * @notice this function will deposit collateral and mint DSC
     * @param collateralAddress: address of token to deposit as collateral
     * @param amountCollateral
     @param _dscAmount the amount of descetralized stable coint to mint
     */
    function depositCollateralAndMintDsc(address _collateralAddress, uint256 _amountCollateral, uint256 _dscAmount)
        public
    {
        depositCollateral(_collateralAddress, _amountCollateral);
        mintDsc(_dscAmount);
    }

    function redeemCollateral(address _token, uint256 _amount) public moreThanZero(_amount) {
        _redeemCollateral(_token, _amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
    * @param _token token address of the collateral to be liquidatd
    * @param _user the use who has broken the helath factor
    * @pram _amount the amount of debt to be covered
     */
    function liquidate(address _token, address _user, uint256 _amount) public moreThanZero(_amount) nonReentrant {
        uint256 startingHealthFactor = _healthFactor(_user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        uint256 tokentFromDebtCovered = getTokenAmountFromUsd(_token, _amount);
        uint256 bonusCollateral = (tokentFromDebtCovered * LIQUIDATOR_BONUS) / LIQUIDATATION_PRECISION;
        uint256 totalCollateral = tokentFromDebtCovered + bonusCollateral;
        _redeemCollateral(_token, totalCollateral, _user, msg.sender);
        _burnDsc(_user, msg.sender, _amount);
        uint256 endingHealthFactor = _healthFactor(_user);
        if (endingHealthFactor <= startingHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc(uint256 _amount) public moreThanZero(_amount) {
     _burnDsc(msg.sender, msg.sender, _amount);
    }

    function redeemCollateralFOrDsc(address _token, uint256 _amountDsc, uint256 _amountCollateral) public {
        burnDsc(_amountDsc);
        redeemCollateral(_token, _amountCollateral);
    }
    /////////////////////////////////////////
    // Private and Internal View Functions ///
    ///////////////////////////////////////////

    function _getAccountInfo(address _user) private view returns (uint256, uint256) {
        return (s_DscMinted[_user], getAccountCollateralValue(_user));
    }

    /*
    * Returns how closea user is to liquidation, if it returns less than one, then the user
    * can be liquidated
     */
    function _healthFactor(address user) internal view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValue) = _getAccountInfo(user);
        uint256 collateralAdjustedForThreshold = (collateralValue * LIQUIDATATION_THRESHOLD) / LIQUIDATATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address _user) internal view {
        uint256 userHealthFactor = _healthFactor(_user);

        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BReaksHealthFactor(userHealthFactor);
        }
    }

    function _burnDsc(address _onBehalfOf, address _dscFrom, uint256 _amount) private {
        s_DscMinted[_onBehalfOf] -= _amount;
        bool success = i_dsc.transferFrom(_dscFrom, address(this), _amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(_amount);
    }

    function _redeemCollateral(address _token, uint256 _amount, address _from, address _to) private {
        s_collateralDeposited[_from][_token] -= _amount;
        emit CollateralRedemed(_from, _to, _token, _amount);
        bool success = IERC20(_token).transfer(_to, _amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }
    //////////////////////////////////////////
    /// Public  and External View Functions //
    //////////////////////////////////////////

    function getTokenAmountFromUsd(address _token, uint256 _usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface pricefeed = AggregatorV3Interface(s_pricefeeds[_token]);
        (, int256 price,,,) = pricefeed.latestRoundData();
        return (_usdAmountInWei * PRECISION) / (uint256(price) * PRICEFEED_PRECISION);
    }

    function getAccountCollateralValue(address _user) public view returns (uint256 totlCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[_user][token];
            totlCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totlCollateralValueInUsd;
    }

    function getUsdValue(address _token, uint256 _amount) public view returns (uint256) {
        AggregatorV3Interface pricefeed = AggregatorV3Interface(s_pricefeeds[_token]);
        (, int256 price,,,) = pricefeed.latestRoundData();
        uint256 priceInUsdWith18Decimals = uint256(price) * PRICEFEED_PRECISION;
        return (priceInUsdWith18Decimals * _amount) / PRECISION;
    }

    function getMIntedDsc() public view returns(uint256) {
        return s_DscMinted[msg.sender];
    }
}
