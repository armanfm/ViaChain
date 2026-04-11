// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 📊 Interface oficial do Chainlink para feeds de preço (oracles descentralizados)
interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (
            uint80,   // id da rodada de dados (round id)
            int256 answer, // 🔥 valor do preço retornado (ex: ETH/USD)
            uint256,  // timestamp de início da rodada
            uint256,  // timestamp de atualização
            uint80    // round id confirmado
        );
}

contract PriceOracle {

    // 📌 referência imutável ao feed de preço (não pode ser alterado depois do deploy)
    AggregatorV3Interface public immutable priceFeed;
  
    // 🏗 construtor recebe endereço do feed Chainlink (ex: ETH/USD)
    constructor(address feedAddress) {
        priceFeed = AggregatorV3Interface(feedAddress);
    }

    // 💰 retorna o preço atual do ETH (ou outro ativo do feed)
    function getETHPrice() public view returns (int) {

        // 📥 chama o oracle e ignora valores não usados
        (, int price,,,) = priceFeed.latestRoundData();

        // 📊 retorna o preço com 8 casas decimais (padrão Chainlink)
        return price;
    }
}
