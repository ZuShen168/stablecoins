// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("user");
    uint256 public constant STARTING_ERC20_BALANCE = 10e18;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, ) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    ///////////////////////////////
    //     Constructor Tests     //
    ///////////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    
    function testRevertIfTokenLengthDoesntMatchPriceFeed() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesLengthMismatch.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /////////////////////////
    //     Price Tests     //
    /////////////////////////
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsdValue = ethAmount * 2000; // ETH price is 2000 USD
        uint256 actualUsdValue = dscEngine.getTokenValueInUsd(weth, ethAmount);
        assertEq(expectedUsdValue, actualUsdValue);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 15e18 * 2000; // 15 ETH worth of USD
        uint256 expectedEthAmount = 15e18;
        uint256 actualEthAmount = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedEthAmount, actualEthAmount);
    }

    //////////////////////////////////////
    //     deposit Collateral tests     //
    //////////////////////////////////////
    function testRevertIfDepositZeroCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), STARTING_ERC20_BALANCE);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.depositCollateral(address(weth), 0);
    }

    function testRevertUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, STARTING_ERC20_BALANCE);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(ranToken), STARTING_ERC20_BALANCE);
    }

    modifier depositedCollateral(){
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), STARTING_ERC20_BALANCE);
        dscEngine.depositCollateral(address(weth), STARTING_ERC20_BALANCE);
        _;
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = dscEngine.getAccountInformation(USER);
        assertEq(totalDscMinted, 0);
        assertEq(totalCollateralValueInUsd, dscEngine.getTokenValueInUsd(weth, STARTING_ERC20_BALANCE));
    }

}