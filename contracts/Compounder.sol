// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol"; //for hardhat artifact
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

import "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";

//import "hardhat/console.sol";

interface IERC20Extented is IERC20 {
    function decimals() external view returns (uint8);
}

contract Compounder is IERC721Receiver, Ownable {
    address constant UniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant deployedNonfungiblePositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant chainLinkFeedRegistry = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf;
    
    INonfungiblePositionManager private constant NFPM = INonfungiblePositionManager(deployedNonfungiblePositionManager);
    FeedRegistryInterface private constant CLFR = FeedRegistryInterface(chainLinkFeedRegistry);
    IUniswapV3Factory private constant uniswapFactory = IUniswapV3Factory(UniswapV3Factory);

    struct Position {
        address token0;
        address token1;
        uint8 decimals0;
        uint8 decimals1;
        uint160 sqrtPrice0X96;
        uint160 sqrtPrice1X96;
        IUniswapV3Pool pool;
    }

    struct TokenCalculation {
        uint256 amount;
        int256 price;
        uint8 decimals;
    }
    
    mapping(address => mapping(address => uint256)) upkeeperToTokenToTokenOwned;
    mapping(uint256 => mapping(address => uint256)) tokenIDtoTokenToExcess;
    mapping(uint256 => Position) public tokenIDtoPosition; //this is initalized for a tokenID when it is sent


    mapping(address => uint256[]) public addressToTokenIds;
    mapping(uint256 => address) public tokenIDtoAddress;
    
    //takes an address and returns an array of the tokenIDs they've staked
    function addressOwns(address addy) public view returns(uint[] memory) {
        return addressToTokenIds[addy];
    }

    //takes a tokenID and returns the address that staked it
    function ownerOfTokenID(uint256 tokenID) public view returns(address) {
        return tokenIDtoAddress[tokenID];
    }

    function positionOfTokenID(uint256 tokenID) public view returns(Position memory) {
        return tokenIDtoPosition[tokenID];
    }

    //stakes a tokenID
    function send(uint256 tokenID) public {
        NFPM.safeTransferFrom(msg.sender, address(this), tokenID);
    }

    //retrieves a NFT based on index
    function retrieve(uint index) public {
        uint256 tokenIDRetrieved = addressToTokenIds[msg.sender][index];

        NFPM.safeTransferFrom(address(this), msg.sender, tokenIDRetrieved);
        delete addressToTokenIds[msg.sender][index];
        delete tokenIDtoAddress[tokenIDRetrieved];
    }

    function sendMultiple(uint256[] memory tokenIDs) public {
        uint i = 0;
        for (; i < tokenIDs.length; i++) {
            send(tokenIDs[i]);
        }
    }

    function retrieveMultiple(uint256[] memory indexes) public {
        uint i = 0;
        for (; i < indexes.length; i++) {
            retrieve(indexes[i]);
        }
    }

    
    function calculatePrincipal(Position memory position, uint256 tokenID, int256 amount0Price, int256 amount1Price) private view returns(uint256) {
        (uint160 sqrtPriceX96, , , , , ,) = position.pool.slot0();
        (, , , , , , , uint128 liquidity , , , , ) = NFPM.positions(tokenID);
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            position.sqrtPrice0X96,
            position.sqrtPrice1X96,
            liquidity
        );
        return calculate(
            TokenCalculation(amount0, amount0Price, position.decimals0),
            TokenCalculation(amount1, amount1Price, position.decimals1)
        );

    }
    

    function findPrice(address tokenAddress) private view returns(int256) { //returns the price in ETH
        if (tokenAddress == WETH) return 10**18; //1 weth is equal to 10^18 wei 
        return CLFR.latestAnswer(tokenAddress, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    }   

    function assetToETH(TokenCalculation memory token) private pure returns(uint256) {
        return Math.mulDiv(token.amount, uint256(token.price), 10**(token.decimals));
    }

    function ETHtoAsset(TokenCalculation memory token) private pure returns(uint256) {
        return Math.mulDiv(token.amount, 10**(token.decimals), uint256(token.price));
    }

    function calculate(TokenCalculation memory tokenA, TokenCalculation memory tokenB) private pure returns(uint256) {
        return assetToETH(tokenA) + assetToETH(tokenB);
    }



    function calculateFees(uint256 excessETH) private view returns (uint256 totalFeesETH) {
         //these represent fees
        uint256 share = Math.mulDiv(excessETH, 3, 100); //3% of remaining includes the caller fee and the platform fee
        uint256 gas = tx.gasprice * 300000; //estimate 300,000 gas limit; this is the gas in wei
        totalFeesETH = share + gas;

        require (excessETH > totalFeesETH);
    }

    function handleExcess(uint256 tokenID, address token, uint8 decimals, uint256 amountCollected, uint256 amountAdded, int256 rate, uint256 earningsInEth, uint256 principalInEth) private {
            //excessETH represents the price of the excess amount of tokens in ETH
            uint256 excessETH = assetToETH(
                TokenCalculation(
                    amountCollected-amountAdded,
                    rate,
                    decimals
                )
            );
            
            uint256 feesInEth = calculateFees(excessETH); //ensures there is enough fees to cover gas
            uint256 excessAfterFeesInEth = excessETH - feesInEth; //remaining goes to an allowance of remainding that can be used for the next


            uint256 feesInToken = ETHtoAsset(
                TokenCalculation(
                    feesInEth,
                    rate,
                    decimals
                )
            );
            uint256 excessAfterFeesInToken = ETHtoAsset(TokenCalculation(excessAfterFeesInEth, rate, decimals));
            
            tokenIDtoTokenToExcess[tokenID][token] += excessAfterFeesInToken;
            upkeeperToTokenToTokenOwned[msg.sender][token] += feesInToken;
    /*
            console.log(earningsInEth);
            console.log(principalInEth);
            console.log(feesInEth);*/
            require(earningsInEth > Math.sqrt(principalInEth * feesInEth), "Doesn't pass the compound requirements");
    }

    struct UpkeepState {
        uint256 amount0collected;
        uint256 amount1collected;
        uint256 amount0added;
        uint256 amount1added;
        int256 token0rate;
        int256 token1rate;
        uint256 earningsInEth;
        uint256 principalInEth;
        uint256 feesInEth;
    }

    function doSingleUpkeep(uint256 tokenID) public {
        UpkeepState memory state;
        Position memory position = tokenIDtoPosition[tokenID];

         
        INonfungiblePositionManager.CollectParams memory CP = INonfungiblePositionManager.CollectParams(tokenID, address(this), type(uint128).max, type(uint128).max);
        (state.amount0collected, state.amount1collected) = NFPM.collect(CP);
        
        //allow for the excess from previous compounds to be used
        state.amount0collected += tokenIDtoTokenToExcess[tokenID][position.token0];
        state.amount1collected += tokenIDtoTokenToExcess[tokenID][position.token1];

        INonfungiblePositionManager.IncreaseLiquidityParams memory IC = INonfungiblePositionManager.IncreaseLiquidityParams(tokenID, state.amount0collected, state.amount1collected, 0, 0, block.timestamp);
        (, state.amount0added, state.amount1added) = NFPM.increaseLiquidity(IC);

        state.token0rate = findPrice(position.token0);
        state.token1rate = findPrice(position.token1);

        state.earningsInEth = calculate(
            TokenCalculation(state.amount0added, state.token0rate, position.decimals0),
            TokenCalculation(state.amount1added, state.token1rate, position.decimals1)
        );

        state.principalInEth = calculatePrincipal(position, tokenID, state.token0rate, state.token1rate);



        if (state.amount0collected == state.amount0added) {
            handleExcess(
                tokenID,
                position.token1,
                position.decimals1,
                state.amount1collected,
                state.amount1added,
                state.token1rate,
                state.earningsInEth,
                state.principalInEth
            );
        } else {
            handleExcess(
                tokenID,
                position.token1,
                position.decimals0,
                state.amount0collected,
                state.amount0added,
                state.token0rate,
                state.earningsInEth,
                state.principalInEth
            );
        }
        
    }

    function onERC721Received( address operator, address from, uint256 tokenID, bytes calldata data ) public override returns (bytes4) {
        require(msg.sender == address(deployedNonfungiblePositionManager), "Not a uniswap position");

        (, , address token0, address token1, uint24 fee, int24 tickLower , int24 tickUpper ,  , , , , ) = NFPM.positions(tokenID);

        //ensures that there is a chainlink ETH oracle pair associated with the tokens
        if (token0 != WETH) {
            require(CLFR.latestAnswer(token0, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) != 0);
        }

        if (token1 != WETH) {
            require(CLFR.latestAnswer(token1, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) != 0);
        }

        tokenIDtoPosition[tokenID] = Position(
            token0,
            token1,
            IERC20Extented(token0).decimals(),
            IERC20Extented(token1).decimals(),
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            IUniswapV3Pool(uniswapFactory.getPool(token0, token1, fee))
        );

        tokenIDtoTokenToExcess[tokenID][token0] = 0;
        tokenIDtoTokenToExcess[tokenID][token1] = 0;
        addressToTokenIds[from].push(tokenID);
        tokenIDtoAddress[tokenID] = from;

        if (IERC20(token0).allowance(address(this), deployedNonfungiblePositionManager) == 0) {
           TransferHelper.safeApprove(token0, deployedNonfungiblePositionManager, type(uint256).max);
        }

        if (IERC20(token1).allowance(address(this), deployedNonfungiblePositionManager) == 0) {
           TransferHelper.safeApprove(token1, deployedNonfungiblePositionManager, type(uint256).max);
        }

        return this.onERC721Received.selector;
    }
}