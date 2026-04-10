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

    address constant ROUTER    = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    bytes32 constant DON_ID    = 0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000;
    uint32  constant GAS_LIMIT = 300000;

    // JS executado no DON — recebe km do taximetro e valida
    // Chainlink assina o resultado antes de enviar ao RideEscrow
    string public constant SOURCE =
        "const kmPercorrido = parseInt(args[0]);"
        "if (isNaN(kmPercorrido) || kmPercorrido <= 0) throw new Error('Invalid km');"
        "return Functions.encodeUint256(kmPercorrido);";

    address public rideEscrow;
    uint64  public subscriptionId;

    mapping(bytes32 => uint256) public requestToRide;
    bytes public s_lastError;

    event KmSolicitado(bytes32 indexed requestId, uint256 indexed rideId, uint256 kmPercorrido);
    event KmValidado(uint256 indexed rideId, uint256 distanciaKm);
    event Response(bytes32 indexed requestId, uint256 indexed rideId, bytes err);

    constructor(
        address _rideEscrow,
        uint64  _subscriptionId
    ) FunctionsClient(ROUTER) {
        require(_rideEscrow != address(0), "Invalid escrow");
        rideEscrow     = _rideEscrow;
        subscriptionId = _subscriptionId;
    }

    // ── Admin ─────────────────────────────────────────────────────

    function setRideEscrow(address _rideEscrow) external onlyOwner {
        require(_rideEscrow != address(0), "Invalid escrow");
        rideEscrow = _rideEscrow;
    }

    function setSubscriptionId(uint64 _subscriptionId) external onlyOwner {
        subscriptionId = _subscriptionId;
    }

    // ── Validacao ─────────────────────────────────────────────────
    // Chamado pelo RideEscrow com km do taximetro (frontend Haversine + GPS)
    // Chainlink valida e assina antes de distribuir pagamento
    function validarKm(
        uint256 rideId,
        uint256 kmPercorrido
    ) external returns (bytes32 requestId) {
        require(msg.sender == rideEscrow, "Only RideEscrow can call");
        require(kmPercorrido > 0, "Invalid km");

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(SOURCE);

        string[] memory args = new string[](1);
        args[0] = _uint2str(kmPercorrido);
        req.setArgs(args);

        bytes32 reqId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            GAS_LIMIT,
            DON_ID
        );

        requestToRide[reqId] = rideId;
        emit KmSolicitado(reqId, rideId, kmPercorrido);
        return reqId;
    }

    // ── Callback Chainlink ────────────────────────────────────────
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
            emit KmValidado(rideId, distanciaKm);
            IRideEscrow(rideEscrow).receberResultadoRota(rideId, distanciaKm);
        }

        emit Response(requestId, rideId, err);
        delete requestToRide[requestId];
    }

    // ── Helper ────────────────────────────────────────────────────
    function _uint2str(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 j = v;
        uint256 len;
        while (j != 0) { len++; j /= 10; }
        bytes memory b = new bytes(len);
        uint256 k = len;
        while (v != 0) { k--; b[k] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return string(b);
    }
}

