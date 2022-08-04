// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol"; //for hardhat artifact
import "hardhat/console.sol";
import "prb-math/contracts/PRBMath.sol";

interface IERC20Extented is IERC20 {
    function decimals() external view returns (uint8);
}

contract Compounder is IERC721Receiver, Ownable {
    address constant deployedNonfungiblePositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant chainLinkFeedRegistry = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf;
    
    INonfungiblePositionManager public constant NFPM = INonfungiblePositionManager(deployedNonfungiblePositionManager);
    FeedRegistryInterface public constant CLFR = FeedRegistryInterface(chainLinkFeedRegistry);
    
    struct Position {
        address token0;
        address token1;
        uint8 decimals0;
        uint8 decimals1;
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




    function findPrice(address tokenAddress) public view returns(int256) { //returns the price in ETH
        if (tokenAddress == WETH) return 10**18; //1 weth is equal to 10^18 wei 
        return CLFR.latestAnswer(tokenAddress, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    }   

    function assetToETH(uint256 amount, int256 price, uint8 decimals) public pure returns(uint256) {
        return PRBMath.mulDiv(amount, uint256(price), 10**(decimals));
    }

    function calculatePrincipal(uint256 amount0, int256 amount0Price, uint8 decimals0, uint256 amount1, int256 amount1Price, uint8 decimals1) private pure returns(uint256) {
        return assetToETH(amount0, amount0Price, decimals0) + assetToETH(amount1, amount1Price, decimals1);
    }


    function manageExcess(uint256 tokenID, address token, uint256 principal, uint256 amountCollected, uint256 amountAdded, int256 tokenPrice, uint8 decimals) private {
        

        uint256 excessAmount = amountCollected - amountAdded;
        uint256 excessETH = assetToETH(excessAmount, tokenPrice, decimals);

        //these represent fees
        uint256 share = PRBMath.mulDiv(excessETH, 3, 100); //3% of remaining includes the caller fee and the platform fee

        uint256 gas = tx.gasprice * 300000; //estimate 300,000 gas limit; this is the gas in wei
        uint256 totalFees = share + gas;

        uint256 remaining = excessETH - share; //remaining goes to an allowance of remainding that can be used for the next
        require (excessETH > totalFees);

        tokenIDtoTokenToExcess[tokenID][token] += remaining;
        upkeeperToTokenToTokenOwned[tx.origin][token] += totalFees; //total fees will be later split with the platform



    }

    function doSingleUpkeep(uint256 tokenID, uint256 deadline) public {

        Position memory position = tokenIDtoPosition[tokenID];

        //temporary solution to approvals -- optimally should be done in the constructor with the 20 or so assets
        if (IERC20(position.token0).allowance(address(this), deployedNonfungiblePositionManager) == 0) {
           TransferHelper.safeApprove(position.token0, deployedNonfungiblePositionManager, type(uint256).max);
        }

        if (IERC20(position.token1).allowance(address(this), deployedNonfungiblePositionManager) == 0) {
           TransferHelper.safeApprove(position.token1, deployedNonfungiblePositionManager, type(uint256).max);
        }
        
        INonfungiblePositionManager.CollectParams memory CP = INonfungiblePositionManager.CollectParams(tokenID, address(this), type(uint128).max, type(uint128).max);
        (uint256 amount0collected, uint256 amount1collected) = NFPM.collect(CP);

        //allow for the excess from previous compounds to be used
        amount0collected += tokenIDtoTokenToExcess[tokenID][position.token0];
        amount1collected += tokenIDtoTokenToExcess[tokenID][position.token1];

        INonfungiblePositionManager.IncreaseLiquidityParams memory IC = INonfungiblePositionManager.IncreaseLiquidityParams(tokenID, amount0collected, amount1collected, 0, 0, deadline);
        (, uint256 amount0added, uint256 amount1added) = NFPM.increaseLiquidity(IC);


        int256 token0rate = findPrice(position.token0);
        int256 token1rate = findPrice(position.token1);

        uint256 principalInEth = calculatePrincipal(
            amount0added, token0rate, position.decimals0,
            amount1added, token1rate, position.decimals1
        );

        if (amount0collected == amount0added) {
            uint256 excessAmount1 = amount1collected - amount1added;
            uint256 excessETH = assetToETH(excessAmount1, token1rate, position.decimals1);
            console.log(excessAmount1);
            console.log(excessETH);
        } else {
            uint256 excessAmount0 = amount0collected - amount0added;
            uint256 excessETH = assetToETH(excessAmount0, token0rate, position.decimals0);
            console.log(excessAmount0);
            console.log(excessETH);
        }
    }

    function onERC721Received( address operator, address from, uint256 tokenID, bytes calldata data ) public override returns (bytes4) {
        require(operator == address(this));

        addressToTokenIds[from].push(tokenID);
        tokenIDtoAddress[tokenID] = from;

        (, , address token0, address token1, , , , , , , , ) = NFPM.positions(tokenID);
        
        tokenIDtoPosition[tokenID] = Position(
            token0,
            token1,
            IERC20Extented(token0).decimals(),
            IERC20Extented(token1).decimals()
        );

        tokenIDtoTokenToExcess[tokenID][token0] = 0;
        tokenIDtoTokenToExcess[tokenID][token1] = 0;

        return this.onERC721Received.selector;
    }
}