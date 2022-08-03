// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

contract CompounderMath {


    function calculateLiqNeeded(int24 tickLow, int24 tickCurrent, int24 tickHigh, uint256 tokenQTY) public pure returns(uint256) {
        uint256 low = TickMath.getSqrtRatioAtTick(tickLow);
        uint256 current = TickMath.getSqrtRatioAtTick(tickCurrent);
        uint256 high = TickMath.getSqrtRatioAtTick(tickHigh);

        uint256 denominator = high - current;

        return tokenQTY;
    }
}