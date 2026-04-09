// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FunctionsClient} from "@chainlink/contracts@1.3.0/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts@1.3.0/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import "@openzeppelin/contracts@4.9.3/access/Ownable.sol";

interface IRideEscrow {
    function receberResultadoRota(uint256 rideId, uint256 distanciaKm) external;
}

contract Rota is FunctionsClient, Ownable {
    using FunctionsRequest for FunctionsRequest.Request;

    // ── Chainlink Config ─────────────────────────────────────────
    address constant ROUTER     = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    bytes32 constant DON_ID     = 0x66756e2d657468657265756d2d7365706c69612d3100000000000000000000;
    uint32  constant GAS_LIMIT  = 300000;

    // ── JS Source (OSRM) ─────────────────────────────────────────
    string public constant SOURCE =
        "const lat1 = args[0];"
        "const lon1 = args[1];"
        "const lat2 = args[2];"
        "const lon2 = args[3];"
        "const osrmRes = await Functions.makeHttpRequest({"
        "  url: `https://router.project-osrm.org/route/v1/driving/${lon1},${lat1};${lon2},${lat2}?overview=false`"
        "});"
        "if (osrmRes.error) throw new Error('Erro na chamada OSRM');"
        "if (osrmRes.data.code !== 'Ok') throw new Error('OSRM: rota nao encontrada');"
        "const distanciaKm = osrmRes.data.routes[0].distance / 1000;"
        "return Functions.encodeUint256(Math.round(distanciaKm));";

    // ── Estado ──────────────────────────────────────────────────
    address public rideEscrow;
    uint64  public subscriptionId;

    mapping(bytes32 => uint256) public requestToRide;
    bytes public s_lastError;

    // ── Eventos ─────────────────────────────────────────────────
    event RotaSolicitada(bytes32 indexed requestId, uint256 indexed rideId);
    event DistanciaCalculada(uint256 indexed rideId, uint256 distanciaKm);
    event Response(bytes32 indexed requestId, uint256 indexed rideId, bytes err);

    // ── Constructor ─────────────────────────────────────────────
    constructor(
        address _rideEscrow,
        uint64  _subscriptionId
    ) FunctionsClient(ROUTER) {
        require(_rideEscrow != address(0), "Invalid escrow");
        rideEscrow     = _rideEscrow;
        subscriptionId = _subscriptionId;
    }

    // ── Admin ───────────────────────────────────────────────────
    function setRideEscrow(address _rideEscrow) external onlyOwner {
        require(_rideEscrow != address(0), "Invalid escrow");
        rideEscrow = _rideEscrow;
    }

    function setSubscriptionId(uint64 _subscriptionId) external onlyOwner {
        subscriptionId = _subscriptionId;
    }

    // ── Cálculo de Distância ────────────────────────────────────
    function calcularDistancia(
        string calldata lat1,
        string calldata lon1,
        string calldata lat2,
        string calldata lon2,
        uint256 rideId
    ) external returns (bytes32 requestId) {
        require(msg.sender == rideEscrow, "Not authorized");

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(SOURCE);

        string;
        args[0] = lat1;
        args[1] = lon1;
        args[2] = lat2;
        args[3] = lon2;
        req.setArgs(args);

        bytes32 reqId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            GAS_LIMIT,
            DON_ID
        );

        requestToRide[reqId] = rideId;

        emit RotaSolicitada(reqId, rideId);
        return reqId;
    }

    // ── Callback Chainlink ──────────────────────────────────────
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        uint256 rideId = requestToRide[requestId];
        require(rideId != 0, "Unknown requestId");

        s_lastError = err;

        if (response.length > 0) {
            uint256 distanciaKm = abi.decode(response, (uint256));

            emit DistanciaCalculada(rideId, distanciaKm);

            IRideEscrow(rideEscrow).receberResultadoRota(
                rideId,
                distanciaKm
            );
        }

        emit Response(requestId, rideId, err);

        delete requestToRide[requestId];
    }
}
