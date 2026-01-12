//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/** @title DSCEngine 
 * @author Zu Shen Ng
 */
contract DSCEngine is ReentrancyGuard {

    ////////////////////
    //     Errors     //
    ////////////////////
    error DSC__MustBeMoreThanZero();
    error DSC__TokenAddressesAndPriceFeedAddressesLengthMismatch();
    error DSC__NotAllowedToken();

    /////////////////////////////
    //     State Variables     //
    /////////////////////////////
    mapping(address token => address priceFeed) private s_priceFeeds; 

    DecentralizedStableCoin private immutable i_dsc;

    ///////////////////////
    //     Modifiers     //
    ///////////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0){
            revert DSC__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if(s_priceFeeds[token] == address(0)){
            revert DSC__NotAllowedToken();
        }
        _;
    }

    ///////////////////////
    //     Functions     //
    ///////////////////////
    constructor(address[] memory tokenAddresses, 
    address[] memory priceFeedAddresses,
    address dscAddress) {
        if(tokenAddresses.length != priceFeedAddresses.length) {
            revert DSC__TokenAddressesAndPriceFeedAddressesLengthMismatch();
        }
        for (uint256 i =0; i< tokenAddresses.length; i++){
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////////////
    //     External Functions     //
    ////////////////////////////////
    function depositCollateralAndMintDsc() external {

    }

    /**
     * @notice Deposits collateral to the engine
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) external moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant {

    }

    function redeemCollateralForDsc() external {

    }

    function redeemCollateral() external {

    }

    function mintDsc() external {

    }

    function burnDsc() external {

    }

    function liquidate() external {

    }

    function getHealthFactor() external view returns (uint256) {

    }
}