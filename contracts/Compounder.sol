// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

contract Compounder is IERC721Receiver {
    address deployedNonfungiblePositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address owner;
    address keeper = 0x9b374bb9e4130a3B926fE56C0849432b664e9420;
    uint128 maxCollect = 340282366920938463463374607431768211455;

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

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
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
    function doSingleUpkeep(uint tokenID, uint amount0Desired, uint amount1Desired, uint amount0Min, uint amount1Min, uint256 deadline) public {
        CollectParams memory CP = CollectParams(tokenID, address(this), maxCollect, maxCollect);
        bytes memory collectcall = abi.encodeWithSignature("collect((uint256,address,uint128,uint128))", CP);
        address(NFPM).call(collectcall);

        IncreaseLiquidityParams memory IC = IncreaseLiquidityParams(tokenID, amount0Desired, amount1Desired, amount0Min, amount1Min, deadline);
        bytes memory increasecall = abi.encodeWithSignature("increaseLiquidity((uint256,uint256,uint256,uint256,uint256,uint256))", IC);
        address(NFPM).call(increasecall);
    }

    function onERC721Received( address operator, address from, uint256 tokenId, bytes calldata data ) public override returns (bytes4) {
        if (operator == address(this)) {
            addressToTokenId[from].push(tokenId);
        }

        return this.onERC721Received.selector;
    }
}
