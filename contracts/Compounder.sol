// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CompounderMath {
    function calculateLiqNeeded(int24 tickLow, int24 tickCurrent, int24 tickHigh, uint256 tokenQTY) public pure returns(uint256 liq) {
        return 1;
    }
}
contract Compounder is IERC721Receiver, Ownable {
    address constant deployedNonfungiblePositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    INonfungiblePositionManager public constant NFPM = INonfungiblePositionManager(deployedNonfungiblePositionManager);
    
    struct Position {
        address token0;
        address token1;
        uint256 unclaimedToken0; //unclaimed on compounder, not on uniswap
        uint256 unclaimedToken1; 
    }

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

    function doSingleUpkeep(uint tokenID, address token0, address token1, uint amount0Desired, uint amount1Desired, uint amount0Min, uint amount1Min, uint256 deadline) public {
        //temporary solution to approvals -- optimally should be done in the constructor with the 20 or so assets
        if (IERC20(token0).allowance(address(this), deployedNonfungiblePositionManager) == 0) {
           IERC20(token0).approve(deployedNonfungiblePositionManager, type(uint256).max);
        }

        if (IERC20(token1).allowance(address(this), deployedNonfungiblePositionManager) == 0) {
           IERC20(token1).approve(deployedNonfungiblePositionManager, type(uint256).max);
        }

        INonfungiblePositionManager.CollectParams memory CP = INonfungiblePositionManager.CollectParams(tokenID, address(this), type(uint128).max, type(uint128).max);
        NFPM.collect(CP);

        INonfungiblePositionManager.IncreaseLiquidityParams memory IC = INonfungiblePositionManager.IncreaseLiquidityParams(tokenID, amount0Desired, amount1Desired, amount0Min, amount1Min, deadline);
        NFPM.increaseLiquidity(IC);
    }

    function onERC721Received( address operator, address from, uint256 tokenID, bytes calldata data ) public override returns (bytes4) {
        require(operator == address(this));

        addressToTokenIds[from].push(tokenID);
        tokenIDtoAddress[tokenID] = from;

        (, , address token0, address token1, , , , , , , , ) = NFPM.positions(tokenID);

        tokenIDtoPosition[tokenID] = Position(
            token0,
            token1,
            0,
            0
        );

        return this.onERC721Received.selector;
    }
}