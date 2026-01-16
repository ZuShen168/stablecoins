//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine 
 * @author Zu Shen Ng
 */
contract DSCEngine is ReentrancyGuard {
    ////////////////////
    //     Errors     //
    ////////////////////
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesLengthMismatch();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreakHealthFactor(uint256 healthFactor);
    error DSGEngine__MintFailed();
    error DSCEngine__HealthFactorOK(uint256 healthFactor);
    error DSCEngine__HealthFactorNotImproved(uint256 healthFactor);

    /////////////////////////////
    //     State Variables     //
    /////////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_allowedTokens;

    ////////////////////
    //     Events     //
    ////////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount);

    DecentralizedStableCoin private immutable i_dsc;

    ///////////////////////
    //     Modifiers     //
    ///////////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    ///////////////////////
    //     Functions     //
    ///////////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesLengthMismatch();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_allowedTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////////////
    //     External Functions     //
    ////////////////////////////////
    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice Deposits collateral to the engine
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc(address tokenCollateraAddress, uint256 amountCollateral, uint256 amountDscToBurn) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateraAddress, amountCollateral);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) public moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSGEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amountDscToBurn) public moreThanZero(amountDscToBurn) {
        _burnDsc(msg.sender, msg.sender, amountDscToBurn);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function liquidate(address collateral, address user, uint256 debtToCover) external moreThanZero(debtToCover) isAllowedToken(collateral) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOK(startingUserHealthFactor);
        }

        uint256 tokenAmountFromDebt = getTokenAmountFromUsd(collateral, debtToCover);

        uint256 bonusCollateral = (tokenAmountFromDebt * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebt + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);

        _burnDsc(user, msg.sender, debtToCover);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved(endingUserHealthFactor);
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view returns (uint256) {}

    ////////////////////////////////
    //     Internal Functions     //
    ////////////////////////////////
    function _burnDsc(address onBehalfOf, address dscFrom, uint256 amountDscToBurn) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address from, address to,address tokenCollateralAddress, uint256 amountCollateral) private {
        s_collateralDeposited[from][tokenCollateralAddress] += amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(to, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user) private view returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) {
        totalDscMinted = s_DSCMinted[user];
        totalCollateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold*PRECISION/totalDscMinted);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreakHealthFactor(healthFactor);
        }
    }

    ///////////////////////////////////
    //     Public View Functions     //
    ///////////////////////////////////
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns(uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for(uint256 i = 0; i<s_allowedTokens.length; i++) {
            address token = s_allowedTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            if (amount > 0) {
                totalCollateralValueInUsd += getTokenValueInUsd(token, amount);
            }
        }
        return totalCollateralValueInUsd;
    }

    function getTokenValueInUsd(address token, uint256 amount) public view returns (uint256) {
        address priceFeedAddress = s_priceFeeds[token];
        (, int256 price, , , ) = AggregatorV3Interface(priceFeedAddress).latestRoundData();
        return (uint256(price) * amount) / 10**AggregatorV3Interface(priceFeedAddress).decimals();
    }

    function getAccountInformation(address user) external view returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) {
        (totalDscMinted, totalCollateralValueInUsd) = _getAccountInformation(user);
    }
}
