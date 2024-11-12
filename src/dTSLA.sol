// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;
/*
*  dTASLA is a synthetic asset that tracks the price of Tesla stock.
* @title dTASLA
*@author: Farooq Ahmed
*
*/

import {ConfirmedOwner} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsClient} from
    "../lib/chainlink-brownie-contracts/contracts/src/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from
    "../lib/chainlink-brownie-contracts/contracts/src/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from
    "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Strings} from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

// D:\dev\defi\rwa-creator\lib\chainlink-brownie-contracts\contracts\src\v0.8\interfaces\AggregatorV3Interface.sol

contract DTesla is ConfirmedOwner, FunctionsClient, ERC20 {
    using FunctionsRequest for FunctionsRequest.Request;
    using Strings for uint256;
    /////////////////////////////////////////////////////////////////
    /////////////// ERRORS ///////////////////////////////////////
    /////////////////////////////////////////////////////////////////
    error dTSLA__NotEnoughCollateral();
    error dTSLA__DoesnotMeetMinimumWithdrawlAmount();
    error dTSLA__TransferFailed();

    /////////////////////////////////////////////////////////////////
    /////////////// state variables ///////////////////////////////////////
    /////////////////////////////////////////////////////////////////
    uint256 constant PRECISION = 1e18;
    // this USD link for demo perpose
    address constant SEPOLIA_TESLA_PRICE_FEED = 0x0c59E3633bAAc79493d908e63626716E204A45eD; // this is actully demo link/USD for price feed perpose

    address constant SEPOLIA_FUNCTION_ROUTER = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    address constant SEPOLIA_USDC_PRICE_FEED = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;//this  is actully  link/USD  price feed for demo perpose
    uint32 constant GAS_LIMIT = 300_000;
    bytes32 constant DON_ID = 0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000;
    address constant SEPOLIA_USDC = 0xc59E3633BAAC79493d908e63626716e204A45EdF; // Example valid address
    uint64 immutable i_subId;
    uint256 constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 constant COLLATERAL_RATIO = 200; // it means we are over collateralized by 2x
    uint256 constant COLLATERAL_PRECISION = 100; // 1e18
    uint256 constant MINIMUM_WITHDRAWL_AMOUNT = 100e18; //  USDC has decimal 6

    enum MintOrRedeem {
        mint,
        redeem
    }

    struct dTslaRequest {
        uint256 amountOfToken;
        address requester;
        MintOrRedeem mintOrRedeem;
    }

    mapping(address user => uint256 pendingWithdrawlAmount) private s_userToWithdrawlAmount;
    mapping(bytes32 requestId => dTslaRequest request) private s_requestIdToRequest;
    /////////////////////////////////////////////////////////////////
    /////////////// STORAGE VARIABLES ////////////////////////
    //////////////////////////////////////////////////////// ////////

    string private s_mintSourceCode;
    string private s_redeemSourceCode;
    uint256 private s_portfolioBalance;

    ////////////////////////////////////////////////////////////////
    ////////////////////// constructor ////////////////////////
    ///////////////////////////////////////////////////////////
    constructor(
        string memory mintSourceCode,
         uint64 subId,
          string memory redeemSourceCode)
        ConfirmedOwner(msg.sender)
        FunctionsClient(SEPOLIA_FUNCTION_ROUTER)
        ERC20("bTsla", "bTsla")
    {
        s_mintSourceCode = mintSourceCode;
        i_subId = subId;
        s_redeemSourceCode = redeemSourceCode;
    }

    /////////////////////////////////////////////////////////////////
    /////////////// Functions ///////////////////////////////////////
    /////////////////////////////////////////////////////////////////
    // send an HTTP request to:
    // 1. See how much tesla is bought
    // 2. If enough tesla is bought in the banck account,
    // 3. Mint dTSLA
    // this is going to be two step function request and recive
    function sendMintRequest(uint256 amountOfTokensToMint) external onlyOwner returns (bytes32) {
        //  tf they want to mint $100 worth of dTSLA
        if (_getCollateralRatioAdjustedTotalBalance(amountOfTokensToMint) > s_portfolioBalance) {
            revert dTSLA__NotEnoughCollateral();
        }
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(s_mintSourceCode);

        bytes32 reqestId = _sendRequest(req.encodeCBOR(), i_subId, GAS_LIMIT, DON_ID);
        s_requestIdToRequest[reqestId] = dTslaRequest(amountOfTokensToMint, msg.sender, MintOrRedeem.mint);
        return reqestId;
    }

    // return the amount of tesala value is stored in the brokage
    // if we have enough tesla  token mint dTSLA
    function _mintFulFillRequest(
        bytes32 requestId, 
        bytes memory response) 
        internal {
        uint256 amountOfTokenToMint = s_requestIdToRequest[requestId].amountOfToken;
        s_portfolioBalance = uint256(bytes32(response));
        // if  tesla token collateral > dTSLA to mint -> mint dTSLA
        // How much TSLA in $$$ do we have
        // how much TSLA are we minting
        if (_getCollateralRatioAdjustedTotalBalance(amountOfTokenToMint) > s_portfolioBalance) {
            revert dTSLA__NotEnoughCollateral();
        }

        if (amountOfTokenToMint > 0) {
            _mint(s_requestIdToRequest[requestId].requester, amountOfTokenToMint);
        }
    }
    // @notice user send request tro sell tesla  for UsDC(Stable coin)
    // this will call our chainlink function call our brokage account do the following
    // 1. Sell tesla
    // 2. Buy USDC
    // 3. sent USD Ccontract to the user to withdraw

    function sendRedeemRequest(uint256 amountdTESLA) external {
        uint256 amountTslaUsdc = getUsdcValueOfUsd(getUsdValueOfTsla(amountdTESLA));
        if (amountTslaUsdc < MINIMUM_WITHDRAWL_AMOUNT) {
            revert dTSLA__DoesnotMeetMinimumWithdrawlAmount();
        }

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(s_redeemSourceCode);
        
        string[] memory args = new string[](2);
        args[0] = amountdTESLA.toString();
        args[1] = amountTslaUsdc.toString();
        req.setArgs(args);
        bytes32 reqestId = _sendRequest(req.encodeCBOR(), i_subId, GAS_LIMIT, DON_ID);
        s_requestIdToRequest[reqestId] = dTslaRequest(amountdTESLA, msg.sender, MintOrRedeem.redeem);
        _burn(msg.sender, amountdTESLA);
    }

    function _redeemFullFillRequest(bytes32 requestId, bytes memory response) internal {
        // assum usdc has 18 decimal places
        uint256 usdcAmount = uint256(bytes32(response));
        if (usdcAmount == 0) {
            uint256 amountOfdTSLABurned = s_requestIdToRequest[requestId].amountOfToken;
            _mint(s_requestIdToRequest[requestId].requester, amountOfdTSLABurned);
            return;
        }
        s_userToWithdrawlAmount[s_requestIdToRequest[requestId].requester] += usdcAmount;
    }

    function withdraw() external {
        uint256 amountToWithdraw = s_userToWithdrawlAmount[msg.sender];
        s_userToWithdrawlAmount[msg.sender] = 0;
        bool succ = ERC20(SEPOLIA_USDC).transfer(msg.sender, amountToWithdraw);
        if (!succ) {
            revert dTSLA__TransferFailed();
        }
    }

    function fulfillRequest(
        bytes32 requestId, 
        bytes memory response, 
        bytes memory /* err*/ ) 
        internal override {
            //  check if the request is mint or redeem
        if (s_requestIdToRequest[requestId].mintOrRedeem == MintOrRedeem.mint) {
            _mintFulFillRequest(requestId, response);
        } else {
            _redeemFullFillRequest(requestId, response);
        }
    }

    function _getCollateralRatioAdjustedTotalBalance(uint256 amountOfTokenToMint) internal view returns (uint256) {
        uint256 calculateNewTotalValue = getCalculatedTotalValue(amountOfTokenToMint);
        return (calculateNewTotalValue * COLLATERAL_RATIO) / COLLATERAL_PRECISION;
    }

    // the new expected total value in USD of all the dTSLA token combined
    function getCalculatedTotalValue(uint256 addedNumberOfTokens) internal view returns (uint256) {
        // if 10 dTSLA  tokens +5 dTSLA tokens = 15 dTSLA tokens*pricce =100
        // 10+5=15*100=1500
        return ((totalSupply() + addedNumberOfTokens) * getTslaPrice()) / PRECISION;
    }

    function getUsdcValueOfUsd(uint256 usdAmount) public view returns (uint256) {
        return (usdAmount * getUsdcPrice()) / PRECISION;
    }

    function getUsdValueOfTsla(uint256 tslaAmount) public view returns (uint256) {
        return (tslaAmount * getTslaPrice()) / PRECISION;
    }

    function getTslaPrice() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(SEPOLIA_TESLA_PRICE_FEED);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price) * ADDITIONAL_FEED_PRECISION; // so that we have 18 decimal places
    }

    function getUsdcPrice() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(SEPOLIA_USDC_PRICE_FEED);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price) * ADDITIONAL_FEED_PRECISION;// so that we have 18 decimal places
    }
    /////////////////////////////////////////////////////////////////
    /////////////// Function view Pure ///////////////////////////
    /////////////////////////////////////////////////////////////////

    function getRequest(bytes32 requestId) public view returns (dTslaRequest memory) {
        return s_requestIdToRequest[requestId];
    }

    function getPendingWithdrawlAmount(address user) public view returns (uint256) {
        return s_userToWithdrawlAmount[user];
    }

    function getPortfolioBalance() public view returns (uint256) {
        return s_portfolioBalance;
    }

    function getMintSourceCode() public view returns (string memory) {
        return s_mintSourceCode;
    }

    function getRedeemSourceCode() public view returns (string memory) {
        return s_redeemSourceCode;
    }

    function getSubId() public view returns (uint64) {
        return i_subId;
    }

    function getCollateralRatio() public view returns (uint256) {
        return COLLATERAL_RATIO;
    }

    function getCollateralPrecision() public view returns (uint256) {
        return COLLATERAL_PRECISION;
    }
}
