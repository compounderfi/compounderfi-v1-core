// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

contract Compounder is IERC721Receiver{
    address deployedNonfungiblePositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address owner;
    address keeper = 0x0268b78B943A3940B4b800A3C2702Fe43Dc7FbC9;
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

    function doSingleUpkeep(validUpkeep params) public{

    }
    function onERC721Received( address operator, address from, uint256 tokenId, bytes calldata data ) public override returns (bytes4) {
        if (operator == address(this)) {
            addressToTokenId[from].push(tokenId);
        }

        return this.onERC721Received.selector;
    }
}