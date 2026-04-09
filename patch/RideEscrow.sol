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
// Interface com Rota.sol — callback do resultado Chainlink OSRM
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

    // Endereço do Cancelamento.sol — único autorizado a chamar marcarCancelado()
    address public cancelamento;

    // Endereço do Rota.sol — único autorizado a chamar receberResultadoRota()
    address public rota;

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

    // Define endereço do Cancelamento.sol após deploy
    function setCancelamento(address _cancelamento) external onlyOwner {
        require(_cancelamento != address(0), "Invalid cancelamento");
        address old = cancelamento;
        cancelamento = _cancelamento;
        emit CancelamentoUpdated(old, _cancelamento);
    }

    // Define endereço do Rota.sol após deploy
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

    // Cada parte saca individualmente
    // Falha de uma carteira nunca bloqueia a outra
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "Nothing to withdraw");

        pendingWithdrawals[msg.sender] = 0; // CEI

        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "Withdraw failed");

        emit Withdrawn(msg.sender, amount);
    }

    // ── Fluxo da corrida ──────────────────────────────────────────

    // Passageiro deposita ETH em escrow — ETH fica travado (staking)
    function createRide(address driver) external payable returns (uint256) {
        require(driver != address(0), "Invalid driver");
        require(governance.isApprovedDriver(driver), "Driver not approved");
        require(msg.value > 0, "Must send ETH");

        rideCounter++;

        rides[rideCounter] = Ride({
            id:                           rideCounter,
            passenger:                    msg.sender,
            driver:                       driver,
            quotedPriceWei:               msg.value,
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
    // Corrida nem começou — não há percurso a calcular
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
    // Motorista não saiu do lugar — não há percurso a calcular
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
    // Inicia timeout de 5 minutos para o passageiro confirmar
    function confirmDestinationReached(uint256 rideId) external {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(msg.sender == ride.driver, "Only driver can confirm");
        require(ride.status == RideStatus.STARTED, "Ride not started");

        ride.status                       = RideStatus.DRIVER_CONFIRMED_DESTINATION;
        ride.driverConfirmedDestinationAt = block.timestamp;

        emit DestinationConfirmedByDriver(rideId, msg.sender, block.timestamp);
    }

    // Passageiro confirma chegada — motorista recebe tudo
    // Corrida concluída normalmente
    function confirmRideCompletion(uint256 rideId) external nonReentrant {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(msg.sender == ride.passenger, "Only passenger can confirm");
        require(
            ride.status == RideStatus.DRIVER_CONFIRMED_DESTINATION,
            "Destination not confirmed by driver"
        );

        uint256 amount      = ride.quotedPriceWei;
        ride.status         = RideStatus.COMPLETED;
        ride.completedAt    = block.timestamp;
        ride.quotedPriceWei = 0;

        _queue(ride.driver, amount);

        emit RideCompleted(rideId, ride.passenger, ride.driver, amount, block.timestamp);
    }

    // Timeout — passageiro não confirmou em 5 minutos
    // Motorista recebe tudo — proteção contra passageiro que some
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
    // Marca a corrida como CANCELLED para que o Rota.sol
    // possa distribuir o pagamento proporcional via receberResultadoRota()
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

    // ─────────────────────────────────────────────────────────────
    // Callback do Rota.sol — chamado automaticamente pelo Chainlink
    // Recebe distância percorrida e distribui pagamento proporcional
    // Motorista recebe até onde foi
    // Passageiro recebe o restante
    // ─────────────────────────────────────────────────────────────
    function receberResultadoRota(
        uint256 rideId,
        uint256 distanciaKm
    ) external nonReentrant onlyRota {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(ride.status == RideStatus.CANCELLED, "Ride not cancelled");
        require(ride.quotedPriceWei > 0, "Already distributed");

        // Calcula proporcional com base no preço/km do motorista
        uint256 pricePerKm   = governance.getDriverPrice(ride.driver);
        uint256 driverAmount = distanciaKm * pricePerKm;

        // Nunca paga mais do que o escrow
        if (driverAmount > ride.quotedPriceWei) {
            driverAmount = ride.quotedPriceWei;
        }

        uint256 passengerAmount = ride.quotedPriceWei - driverAmount;

        // CEI — zera escrow antes de distribuir
        ride.quotedPriceWei = 0;

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
