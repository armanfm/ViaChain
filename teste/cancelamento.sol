// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts@4.9.3/access/Ownable.sol";

interface IRota {
    function calcularDistancia(
        string calldata lat1,
        string calldata lon1,
        string calldata lat2,
        string calldata lon2,
        uint256 rideId
    ) external returns (bytes32 requestId);
}

interface IRideEscrow {
    function marcarCancelado(uint256 rideId) external;
}

contract Cancelamento is Ownable {

    IRota       public rota;
    IRideEscrow public escrow;
    address     public systemOperator;

    event SystemOperatorUpdated(address indexed old, address indexed novo);
    event CancelamentoSolicitado(uint256 indexed rideId, address indexed executor);

    modifier onlySystemOperator() {
        require(
            msg.sender == systemOperator || msg.sender == owner(),
            "Not system operator"
        );
        _;
    }

    constructor(address _rota, address _escrow) {
        require(_rota   != address(0), "Invalid rota");
        require(_escrow != address(0), "Invalid escrow");
        rota   = IRota(_rota);
        escrow = IRideEscrow(_escrow);
    }

    function setSystemOperator(address novo) external onlyOwner {
        require(novo != address(0), "Invalid operator");
        address old = systemOperator;
        systemOperator = novo;
        emit SystemOperatorUpdated(old, novo);
    }

    function setRota(address _rota) external onlyOwner {
        require(_rota != address(0), "Invalid rota");
        rota = IRota(_rota);
    }

    function setEscrow(address _escrow) external onlyOwner {
        require(_escrow != address(0), "Invalid escrow");
        escrow = IRideEscrow(_escrow);
    }

    // Coordenadas empacotadas em bytes para evitar Stack too deep
    // Backend monta assim antes de chamar:
    // coords = abi.encode(latAtual, lonAtual, latDestino, lonDestino)
    function cancelAfterStart(
        uint256 rideId,
        bytes calldata coords  // abi.encode(lat1, lon1, lat2, lon2)
    ) external onlySystemOperator {

        // Desempacota as coordenadas
        (
            string memory lat1,
            string memory lon1,
            string memory lat2,
            string memory lon2
        ) = abi.decode(coords, (string, string, string, string));

        // Marca corrida como cancelada no RideEscrow
        escrow.marcarCancelado(rideId);

        // Chainlink OSRM calcula distância percorrida
        rota.calcularDistancia(lat1, lon1, lat2, lon2, rideId);

        emit CancelamentoSolicitado(rideId, msg.sender);
    }
}
