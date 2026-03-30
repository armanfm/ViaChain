// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Interface oficial Chainlink
interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (
            uint80,
            int256 answer,
            uint256,
            uint256,
            uint80
        );
}

contract PriceOracle {
  AggregatorV3Interface public immutable priceFeed;
  
    constructor(address feedAddress) {
        priceFeed = AggregatorV3Interface(feedAddress);
    }

    function getETHPrice() public view returns (int) {
        (, int price,,,) = priceFeed.latestRoundData();
        return price; // preço com 8 casas decimais
    }
}
