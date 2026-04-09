// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts@4.9.3/access/Ownable.sol";
import "@openzeppelin/contracts@4.9.3/security/ReentrancyGuard.sol";

// ─────────────────────────────────────────────────────────────────
// Interface com ViaChainGovernance
// ─────────────────────────────────────────────────────────────────
interface IGovernance {
    function isApprovedDriver(address driver) external view returns (bool);
    function getDriverPrice(address driver) external view returns (uint256);
}

// ─────────────────────────────────────────────────────────────────
// Interface com Rota.sol — Chainlink Functions + OSRM
// ─────────────────────────────────────────────────────────────────
interface IRota {
    function calcularDistancia(
        string calldata lat1,
        string calldata lon1,
        string calldata lat2,
        string calldata lon2,
        uint256 rideId
    ) external returns (bytes32 requestId);
}

contract RideEscrow is ReentrancyGuard, Ownable {

    IGovernance public governance;

    uint256 public rideCounter;
    uint256 public constant PASSENGER_CONFIRMATION_TIMEOUT = 5 minutes;

    address public systemOperator;
    address public cancelamento; // Cancelamento.sol
    address public rota;         // Rota.sol

    // ── Pull Payment ──────────────────────────────────────────────
    mapping(address => uint256) public pendingWithdrawals;

    enum RideStatus {
        NONE,
        CREATED,
        ACCEPTED,
        STARTED,
        DRIVER_CONFIRMED_DESTINATION,
        COMPLETED,
        CANCELLED,
        DRIVER_REJECTED
    }

    struct Ride {
        uint256 id;
        address passenger;
        address driver;
        uint256 quotedPriceWei;

        // Coordenadas gravadas on-chain no createRide()
        // Usadas pelo Rota.sol no cancelamento e confirmação
        // Calculadas pelo OSRM antes do createRide() — sem Nominatim on-chain
        string latOrigem;
        string lonOrigem;
        string latDestino;
        string lonDestino;

        uint256 createdAt;
        uint256 acceptedAt;
        uint256 startedAt;
        uint256 driverConfirmedDestinationAt;
        uint256 completedAt;
        RideStatus status;
    }

    mapping(uint256 => Ride) public rides;

    // ── Eventos ───────────────────────────────────────────────────
    event SystemOperatorUpdated(address indexed old, address indexed novo);
    event CancelamentoUpdated(address indexed old, address indexed novo);
    event RotaUpdated(address indexed old, address indexed novo);
    event WithdrawalQueued(address indexed recipient, uint256 amount);
    event Withdrawn(address indexed recipient, uint256 amount);

    event RideCreated(
        uint256 indexed rideId,
        address indexed passenger,
        address indexed driver,
        uint256 quotedPriceWei,
        uint256 createdAt
    );
    event RideAccepted(
        uint256 indexed rideId,
        address indexed driver,
        uint256 acceptedAt
    );
    event RideRejected(
        uint256 indexed rideId,
        address indexed driver,
        uint256 refundedAmountWei,
        uint256 rejectedAt
    );
    event RideStarted(
        uint256 indexed rideId,
        address indexed passenger,
        uint256 startedAt
    );
    event DestinationConfirmedByDriver(
        uint256 indexed rideId,
        address indexed driver,
        uint256 confirmedAt
    );
    event RideCompleted(
        uint256 indexed rideId,
        address indexed passenger,
        address indexed driver,
        uint256 paidToDriverWei,
        uint256 completedAt
    );
    event RideCompletedByTimeout(
        uint256 indexed rideId,
        address indexed executor,
        address indexed driver,
        uint256 paidToDriverWei,
        uint256 completedAt
    );
    event RideCancelledBeforeStart(
        uint256 indexed rideId,
        address indexed cancelledBy,
        uint256 refundedToPassengerWei,
        uint256 cancelledAt
    );
    event RideMarcadaCancelada(
        uint256 indexed rideId,
        uint256 cancelledAt
    );
    event PagamentoProporcionalDistribuido(
        uint256 indexed rideId,
        uint256 distanciaKm,
        uint256 paidToDriverWei,
        uint256 refundedToPassengerWei
    );

    // ── Modifiers ─────────────────────────────────────────────────
    modifier onlySystemOperator() {
        require(
            msg.sender == systemOperator || msg.sender == owner(),
            "Not system operator"
        );
        _;
    }

    modifier onlyCancelamento() {
        require(msg.sender == cancelamento, "Only Cancelamento contract");
        _;
    }

    modifier onlyRota() {
        require(msg.sender == rota, "Only Rota contract");
        _;
    }

    // ── Constructor ───────────────────────────────────────────────
    constructor(address governanceAddress) {
        require(governanceAddress != address(0), "Invalid governance");
        governance = IGovernance(governanceAddress);
    }

    // ── Admin ─────────────────────────────────────────────────────

    function setSystemOperator(address novo) external onlyOwner {
        require(novo != address(0), "Invalid operator");
        address old = systemOperator;
        systemOperator = novo;
        emit SystemOperatorUpdated(old, novo);
    }

    function setCancelamento(address _cancelamento) external onlyOwner {
        require(_cancelamento != address(0), "Invalid cancelamento");
        address old = cancelamento;
        cancelamento = _cancelamento;
        emit CancelamentoUpdated(old, _cancelamento);
    }

    function setRota(address _rota) external onlyOwner {
        require(_rota != address(0), "Invalid rota");
        address old = rota;
        rota = _rota;
        emit RotaUpdated(old, _rota);
    }

    // ── Pull Payment ──────────────────────────────────────────────

    function _queue(address recipient, uint256 amount) internal {
        pendingWithdrawals[recipient] += amount;
        emit WithdrawalQueued(recipient, amount);
    }

    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "Nothing to withdraw");

        pendingWithdrawals[msg.sender] = 0; // CEI

        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "Withdraw failed");

        emit Withdrawn(msg.sender, amount);
    }

    // ── Fluxo da corrida ──────────────────────────────────────────

    // Frontend calcula lat/lon via OSRM antes de chamar
    // Coordenadas gravadas on-chain — usadas no cancelamento e confirmação
    // Sem Nominatim on-chain — sem rate limit
    function createRide(
        address driver,
        string calldata latOrigem,
        string calldata lonOrigem,
        string calldata latDestino,
        string calldata lonDestino
    ) external payable returns (uint256) {
        require(driver != address(0), "Invalid driver");
        require(governance.isApprovedDriver(driver), "Driver not approved");
        require(bytes(latOrigem).length > 0, "Invalid latOrigem");
        require(bytes(lonOrigem).length > 0, "Invalid lonOrigem");
        require(bytes(latDestino).length > 0, "Invalid latDestino");
        require(bytes(lonDestino).length > 0, "Invalid lonDestino");
        require(msg.value > 0, "Must send ETH");

        rideCounter++;

        rides[rideCounter] = Ride({
            id:                           rideCounter,
            passenger:                    msg.sender,
            driver:                       driver,
            quotedPriceWei:               msg.value,
            latOrigem:                    latOrigem,
            lonOrigem:                    lonOrigem,
            latDestino:                   latDestino,
            lonDestino:                   lonDestino,
            createdAt:                    block.timestamp,
            acceptedAt:                   0,
            startedAt:                    0,
            driverConfirmedDestinationAt: 0,
            completedAt:                  0,
            status:                       RideStatus.CREATED
        });

        emit RideCreated(rideCounter, msg.sender, driver, msg.value, block.timestamp);
        return rideCounter;
    }

    // Motorista aceita a corrida
    function acceptRide(uint256 rideId) external {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(msg.sender == ride.driver, "Only driver can accept");
        require(governance.isApprovedDriver(msg.sender), "Driver not approved");
        require(ride.status == RideStatus.CREATED, "Invalid ride state");

        ride.status     = RideStatus.ACCEPTED;
        ride.acceptedAt = block.timestamp;

        emit RideAccepted(rideId, msg.sender, block.timestamp);
    }

    // Motorista rejeita — ETH volta integralmente ao passageiro
    // Não saiu do lugar — sem percurso a calcular
    function rejectRide(uint256 rideId) external nonReentrant {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(msg.sender == ride.driver, "Only driver can reject");
        require(ride.status == RideStatus.CREATED, "Invalid ride state");

        uint256 amount      = ride.quotedPriceWei;
        ride.status         = RideStatus.DRIVER_REJECTED;
        ride.quotedPriceWei = 0;

        _queue(ride.passenger, amount);

        emit RideRejected(rideId, msg.sender, amount, block.timestamp);
    }

    // Cancelamento ANTES do início — ETH volta integralmente ao passageiro
    // Motorista não saiu do lugar — sem percurso a calcular
    function cancelBeforeStart(uint256 rideId) external nonReentrant {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(msg.sender == ride.passenger, "Only passenger can cancel");
        require(
            ride.status == RideStatus.CREATED ||
            ride.status == RideStatus.ACCEPTED,
            "Ride already started"
        );

        uint256 amount      = ride.quotedPriceWei;
        ride.status         = RideStatus.CANCELLED;
        ride.quotedPriceWei = 0;

        _queue(ride.passenger, amount);

        emit RideCancelledBeforeStart(rideId, msg.sender, amount, block.timestamp);
    }

    // Passageiro confirma embarque — corrida iniciada
    // A partir daqui qualquer cancelamento aciona o Rota.sol
    function startRide(uint256 rideId) external {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(msg.sender == ride.passenger, "Only passenger can start");
        require(ride.status == RideStatus.ACCEPTED, "Ride not accepted");

        ride.status    = RideStatus.STARTED;
        ride.startedAt = block.timestamp;

        emit RideStarted(rideId, msg.sender, block.timestamp);
    }

    // Motorista confirma chegada ao destino
    // Aciona Rota.sol — OSRM valida km reais percorridos
    // Coordenadas já estão gravadas on-chain desde o createRide()
    function confirmDestinationReached(uint256 rideId) external {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(msg.sender == ride.driver, "Only driver can confirm");
        require(ride.status == RideStatus.STARTED, "Ride not started");

        ride.status                       = RideStatus.DRIVER_CONFIRMED_DESTINATION;
        ride.driverConfirmedDestinationAt = block.timestamp;

        // Aciona Rota.sol com coordenadas gravadas on-chain
        // OSRM calcula distância real origem → destino
        // Resultado volta via receberResultadoRota()
        IRota(rota).calcularDistancia(
            ride.latOrigem,
            ride.lonOrigem,
            ride.latDestino,
            ride.lonDestino,
            rideId
        );

        emit DestinationConfirmedByDriver(rideId, msg.sender, block.timestamp);
    }

    // Passageiro confirma chegada — motorista recebe via Pull Payment
    // receberResultadoRota() já calculou o valor proporcional
    function confirmRideCompletion(uint256 rideId) external nonReentrant {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(msg.sender == ride.passenger, "Only passenger can confirm");
        require(
            ride.status == RideStatus.COMPLETED,
            "Ride not completed by oracle yet"
        );

        // Pagamento já foi distribuído pelo receberResultadoRota()
        // Passageiro só confirma — saca via withdraw()
        emit RideCompleted(
            rideId,
            ride.passenger,
            ride.driver,
            ride.quotedPriceWei,
            block.timestamp
        );
    }

    // Timeout — passageiro não confirmou em 5 minutos
    // Motorista recebe tudo via Pull Payment
    function finalizeAfterTimeout(uint256 rideId) external nonReentrant {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(
            ride.status == RideStatus.DRIVER_CONFIRMED_DESTINATION,
            "Timeout not available"
        );
        require(
            block.timestamp >= ride.driverConfirmedDestinationAt + PASSENGER_CONFIRMATION_TIMEOUT,
            "Timeout not reached"
        );

        uint256 amount      = ride.quotedPriceWei;
        ride.status         = RideStatus.COMPLETED;
        ride.completedAt    = block.timestamp;
        ride.quotedPriceWei = 0;

        _queue(ride.driver, amount);

        emit RideCompletedByTimeout(rideId, msg.sender, ride.driver, amount, block.timestamp);
    }

    // ─────────────────────────────────────────────────────────────
    // Chamado pelo Cancelamento.sol
    // Marca corrida como CANCELLED para o Rota.sol distribuir
    // Coordenadas já estão on-chain — Cancelamento.sol as lê daqui
    // ─────────────────────────────────────────────────────────────
    function marcarCancelado(uint256 rideId) external onlyCancelamento {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(
            ride.status == RideStatus.STARTED ||
            ride.status == RideStatus.DRIVER_CONFIRMED_DESTINATION,
            "Ride not eligible"
        );

        ride.status      = RideStatus.CANCELLED;
        ride.completedAt = block.timestamp;

        emit RideMarcadaCancelada(rideId, block.timestamp);
    }

    // Retorna coordenadas gravadas on-chain
    // Usado pelo Cancelamento.sol para passar ao Rota.sol
    function getRideCoords(uint256 rideId) external view returns (
        string memory latOrigem,
        string memory lonOrigem,
        string memory latDestino,
        string memory lonDestino
    ) {
        Ride storage ride = rides[rideId];
        require(ride.id != 0, "Ride does not exist");
        return (ride.latOrigem, ride.lonOrigem, ride.latDestino, ride.lonDestino);
    }

    // ─────────────────────────────────────────────────────────────
    // Callback do Rota.sol — chamado automaticamente pelo Chainlink
    // Recebe km reais e distribui pagamento proporcional
    // ─────────────────────────────────────────────────────────────
    function receberResultadoRota(
        uint256 rideId,
        uint256 distanciaKm
    ) external nonReentrant onlyRota {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(
            ride.status == RideStatus.CANCELLED ||
            ride.status == RideStatus.DRIVER_CONFIRMED_DESTINATION,
            "Invalid status"
        );
        require(ride.quotedPriceWei > 0, "Already distributed");

        uint256 pricePerKm   = governance.getDriverPrice(ride.driver);
        uint256 driverAmount = distanciaKm * pricePerKm;

        // Nunca paga mais do que o escrow
        if (driverAmount > ride.quotedPriceWei) {
            driverAmount = ride.quotedPriceWei;
        }

        uint256 passengerAmount = ride.quotedPriceWei - driverAmount;

        // CEI — zera escrow antes de distribuir
        ride.quotedPriceWei = 0;
        ride.status         = RideStatus.COMPLETED;
        ride.completedAt    = block.timestamp;

        // Pull Payment — cada um saca individualmente
        if (driverAmount    > 0) _queue(ride.driver,    driverAmount);
        if (passengerAmount > 0) _queue(ride.passenger, passengerAmount);

        emit PagamentoProporcionalDistribuido(
            rideId,
            distanciaKm,
            driverAmount,
            passengerAmount
        );
    }

    // ── Views ─────────────────────────────────────────────────────

    function getRide(uint256 rideId) external view returns (Ride memory) {
        require(rides[rideId].id != 0, "Ride does not exist");
        return rides[rideId];
    }

    function getPendingWithdrawal(address account) external view returns (uint256) {
        return pendingWithdrawals[account];
    }
}
