// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

contract Compounder is IERC721Receiver {
    address deployedNonfungiblePositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address owner;
    address keeper = 0x9b374bb9e4130a3B926fE56C0849432b664e9420;
    uint128 maxCollect = 340282366920938463463374607431768211455;
    uint256 maxSpend = 115792089237316195423570985008687907853269984665640564039457584007913129639935
    INonfungiblePositionManager NFPM = INonfungiblePositionManager(deployedNonfungiblePositionManager);

    constructor() {
        owner = msg.sender;
    }


    mapping(address => uint[]) public addressToTokenId;

    struct validUpkeep {
        uint tokenID; //the tokenID that is valid for upkeep
        uint token0; //amount of token0 that is compounded, with fees deducted
        uint token1; //amount of token0 that is compounded, with fees deducted
    }

    
    function addressToSentIn(address addy) public view returns(uint[] memory) {
        return addressToTokenId[addy];
    }

    function send(uint256 tokenID) public {
        NFPM.safeTransferFrom(msg.sender, address(this), tokenID);
    }

    function retrieve(uint index) public {
        NFPM.safeTransferFrom(address(this), msg.sender, addressToTokenId[msg.sender][index]);
        delete addressToTokenId[msg.sender][index];
    }

    function sendMultiple(uint256[] memory tokenIDs) public {
        for (uint i = 0; i < tokenIDs.length; i++) {
            send(tokenIDs[i]);
        }
    }

    function retrieveMultiple(uint256[] memory indexes) public {
        for (uint i = 0; i < indexes.length; i++) {
            retrieve(indexes[i]);
        }
    }

    //function doSingleUpkeep(validUpkeep memory params)
    function doSingleUpkeep(uint tokenID, address token0, address token1, uint amount0Desired, uint amount1Desired, uint amount0Min, uint amount1Min, uint256 deadline) public {
        if (IERC20(token0).allowance(address(this), deployedNonfungiblePositionManager) == 0) {
           IERC20(token0).approve(deployedNonfungiblePositionManager, maxSpend);
        }

        if (IERC20(token1).allowance(address(this), deployedNonfungiblePositionManager) == 0) {
           IERC20(token1).approve(deployedNonfungiblePositionManager, maxSpend);
        }

        INonfungiblePositionManager.CollectParams memory CP = INonfungiblePositionManager.CollectParams(tokenID, address(this), maxCollect, maxCollect);
        NFPM.collect(CP);

        INonfungiblePositionManager.IncreaseLiquidityParams memory IC = INonfungiblePositionManager.IncreaseLiquidityParams(tokenID, amount0Desired, amount1Desired, amount0Min, amount1Min, deadline);
        NFPM.increaseLiquidity(IC);
    }

    function onERC721Received( address operator, address from, uint256 tokenID, bytes calldata data ) public override returns (bytes4) {
        if (operator == address(this)) {
            addressToTokenId[from].push(tokenID);
        }

        return this.onERC721Received.selector;
    }
}
