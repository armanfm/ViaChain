// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 🔐 Controle de acesso baseado em owner
import "@openzeppelin/contracts@4.9.3/access/Ownable.sol";

// 🛡 proteção contra reentrância (evita ataques em funções de saque e liquidação)
import "@openzeppelin/contracts@4.9.3/security/ReentrancyGuard.sol";

// 📡 interface com o contrato de governança (drivers aprovados e preços)
interface IGovernance {
    function isApprovedDriver(address driver) external view returns (bool);
    function getDriverPrice(address driver) external view returns (uint256);
}

contract RideEscrow is ReentrancyGuard, Ownable {

    // 🧠 referência ao contrato de governança
    IGovernance public governance;

    // 🔢 contador de corridas
    uint256 public rideCounter;

    // ⏱ constante de timeout (não usada diretamente aqui, mas reservada)
    uint256 public constant PASSENGER_CONFIRMATION_TIMEOUT = 5 minutes;

    // 🏛 operador do sistema (admin secundário)
    address public systemOperator;

    // 💰 saldo pendente de saque (pull payment pattern)
    mapping(address => uint256) public pendingWithdrawals;

    // 📊 estados possíveis de uma corrida
    enum RideStatus {
        NONE,
        CREATED,
        ACCEPTED,
        STARTED,
        COMPLETED,
        CANCELLED,
        DRIVER_REJECTED
    }

    // 🧾 estrutura principal da corrida
    struct Ride {
        uint256 id;
        address passenger;
        address driver;
        uint256 quotedPriceWei;
        string latOrigem;
        string lonOrigem;
        string latDestino;
        string lonDestino;
        uint256 createdAt;
        uint256 acceptedAt;
        uint256 startedAt;
        uint256 completedAt;
        RideStatus status;
    }

    // 📦 armazenamento de corridas
    mapping(uint256 => Ride) public rides;

    // 📡 eventos do sistema
    event SystemOperatorUpdated(address indexed old, address indexed novo);
    event WithdrawalQueued(address indexed recipient, uint256 amount);
    event Withdrawn(address indexed recipient, uint256 amount);

    event RideCreated(uint256 indexed rideId, address indexed passenger, address indexed driver, uint256 quotedPriceWei, uint256 createdAt);
    event RideAccepted(uint256 indexed rideId, address indexed driver, uint256 acceptedAt);
    event RideRejected(uint256 indexed rideId, address indexed driver, uint256 refundedAmountWei, uint256 rejectedAt);

    event RideStarted(uint256 indexed rideId, address indexed passenger, uint256 startedAt);

    event RideCompleted(
        uint256 indexed rideId,
        address indexed passenger,
        address indexed driver,
        uint256 paidToDriverWei,
        uint256 refundedToPassengerWei,
        uint256 completedAt
    );

    event RideCancelledBeforeStart(uint256 indexed rideId, address indexed cancelledBy, uint256 refundedToPassengerWei, uint256 cancelledAt);

    event RideCancelledAfterStart(uint256 indexed rideId, address indexed cancelledBy, uint256 paidToDriverWei, uint256 refundedToPassengerWei, uint256 cancelledAt);

    event PagamentoProporcionalDistribuido(
        uint256 indexed rideId,
        uint256 kmPercorrido,
        uint256 paidToDriverWei,
        uint256 refundedToPassengerWei
    );

    // 🔐 permite apenas owner ou systemOperator executar funções críticas
    modifier onlySystemOperator() {
        require(msg.sender == systemOperator || msg.sender == owner(), "Not system operator");
        _;
    }

    // 🏗 construtor define contrato de governança
    constructor(address governanceAddress) {
        require(governanceAddress != address(0), "Invalid governance");
        governance = IGovernance(governanceAddress);
    }

    // ⚙️ define operador do sistema
    function setSystemOperator(address novo) external onlyOwner {
        require(novo != address(0), "Invalid operator");

        address old = systemOperator;
        systemOperator = novo;

        emit SystemOperatorUpdated(old, novo);
    }

    // 💰 coloca valores em fila de saque (evita transfer direta)
    function _queue(address recipient, uint256 amount) internal {
        pendingWithdrawals[recipient] += amount;
        emit WithdrawalQueued(recipient, amount);
    }

    // 💸 saque seguro (pull payment)
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "Nothing to withdraw");

        pendingWithdrawals[msg.sender] = 0;

        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "Withdraw failed");

        emit Withdrawn(msg.sender, amount);
    }

    // ─────────────────────────────────────────────────────────────
    // 🚗 FLUXO PRINCIPAL DE CORRIDAS
    // ─────────────────────────────────────────────────────────────

    // 🧾 criação da corrida pelo passageiro (stake em ETH)
    function createRide(
        address driver,
        string calldata latOrigem,
        string calldata lonOrigem,
        string calldata latDestino,
        string calldata lonDestino
    ) external payable returns (uint256) {

        require(driver != address(0), "Invalid driver");
        require(governance.isApprovedDriver(driver), "Driver not approved");

        // 📍 valida coordenadas
        require(bytes(latOrigem).length > 0, "Invalid latOrigem");
        require(bytes(lonOrigem).length > 0, "Invalid lonOrigem");
        require(bytes(latDestino).length > 0, "Invalid latDestino");
        require(bytes(lonDestino).length > 0, "Invalid lonDestino");

        // 💰 deve enviar valor da corrida
        require(msg.value > 0, "Must send ETH");

        rideCounter++;

        // 🧱 cria estrutura da corrida
        rides[rideCounter] = Ride({
            id: rideCounter,
            passenger: msg.sender,
            driver: driver,
            quotedPriceWei: msg.value,
            latOrigem: latOrigem,
            lonOrigem: lonOrigem,
            latDestino: latDestino,
            lonDestino: lonDestino,
            createdAt: block.timestamp,
            acceptedAt: 0,
            startedAt: 0,
            completedAt: 0,
            status: RideStatus.CREATED
        });

        emit RideCreated(rideCounter, msg.sender, driver, msg.value, block.timestamp);
        return rideCounter;
    }

    // 🚖 motorista aceita corrida
    function acceptRide(uint256 rideId) external {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(msg.sender == ride.driver, "Only driver can accept");
        require(governance.isApprovedDriver(msg.sender), "Driver not approved");
        require(ride.status == RideStatus.CREATED, "Invalid ride state");

        ride.status = RideStatus.ACCEPTED;
        ride.acceptedAt = block.timestamp;

        emit RideAccepted(rideId, msg.sender, block.timestamp);
    }

    // ❌ motorista rejeita corrida (reembolso total)
    function rejectRide(uint256 rideId) external nonReentrant {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(msg.sender == ride.driver, "Only driver can reject");
        require(ride.status == RideStatus.CREATED, "Invalid ride state");

        uint256 amount = ride.quotedPriceWei;

        ride.status = RideStatus.DRIVER_REJECTED;
        ride.quotedPriceWei = 0;

        _queue(ride.passenger, amount);

        emit RideRejected(rideId, msg.sender, amount, block.timestamp);
    }

    // 🚫 cancelamento antes de iniciar (100% reembolso)
    function cancelBeforeStart(uint256 rideId) external nonReentrant {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(msg.sender == ride.passenger, "Only passenger can cancel");

        require(
            ride.status == RideStatus.CREATED ||
            ride.status == RideStatus.ACCEPTED,
            "Ride already started"
        );

        uint256 amount = ride.quotedPriceWei;

        ride.status = RideStatus.CANCELLED;
        ride.quotedPriceWei = 0;

        _queue(ride.passenger, amount);

        emit RideCancelledBeforeStart(rideId, msg.sender, amount, block.timestamp);
    }

    // 🚦 início da corrida (confirmado pelo passageiro)
    function startRide(uint256 rideId) external {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(msg.sender == ride.passenger, "Only passenger can start");
        require(ride.status == RideStatus.ACCEPTED, "Ride not accepted");

        ride.status = RideStatus.STARTED;
        ride.startedAt = block.timestamp;

        emit RideStarted(rideId, msg.sender, block.timestamp);
    }

    // 💰 distribuição proporcional baseada em km rodado
    function _distribuir(Ride storage ride, uint256 rideId, uint256 kmPercorrido) internal {

        uint256 pricePerKm = governance.getDriverPrice(ride.driver);

        uint256 driverAmount = kmPercorrido * pricePerKm;

        // ⚠️ limita ao valor depositado
        if (driverAmount > ride.quotedPriceWei) {
            driverAmount = ride.quotedPriceWei;
        }

        uint256 passengerAmount = ride.quotedPriceWei - driverAmount;

        ride.quotedPriceWei = 0;
        ride.status = RideStatus.COMPLETED;
        ride.completedAt = block.timestamp;

        if (driverAmount > 0) _queue(ride.driver, driverAmount);
        if (passengerAmount > 0) _queue(ride.passenger, passengerAmount);

        emit PagamentoProporcionalDistribuido(
            rideId,
            kmPercorrido,
            driverAmount,
            passengerAmount
        );
    }

    // 🚕 finalização pelo motorista
    function confirmDestinationReached(uint256 rideId, uint256 kmPercorrido)
        external
        nonReentrant
    {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(msg.sender == ride.driver, "Only driver can confirm");
        require(ride.status == RideStatus.STARTED, "Ride not started");
        require(kmPercorrido > 0, "Invalid km");

        _distribuir(ride, rideId, kmPercorrido);

        emit RideCompleted(
            rideId,
            ride.passenger,
            ride.driver,
            pendingWithdrawals[ride.driver],
            pendingWithdrawals[ride.passenger],
            block.timestamp
        );
    }

    // 🚕 finalização pelo passageiro
    function confirmRideCompletion(uint256 rideId, uint256 kmPercorrido)
        external
        nonReentrant
    {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(msg.sender == ride.passenger, "Only passenger can confirm");
        require(ride.status == RideStatus.STARTED, "Ride not started");
        require(kmPercorrido > 0, "Invalid km");

        _distribuir(ride, rideId, kmPercorrido);

        emit RideCompleted(
            rideId,
            ride.passenger,
            ride.driver,
            pendingWithdrawals[ride.driver],
            pendingWithdrawals[ride.passenger],
            block.timestamp
        );
    }

    // 🚫 cancelamento após início (pagamento proporcional)
    function cancelAfterStart(uint256 rideId, uint256 kmPercorrido)
        external
        nonReentrant
    {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(
            msg.sender == ride.passenger || msg.sender == ride.driver,
            "Not authorized"
        );
        require(ride.status == RideStatus.STARTED, "Ride not started");

        _distribuir(ride, rideId, kmPercorrido);

        emit RideCancelledAfterStart(
            rideId,
            msg.sender,
            pendingWithdrawals[ride.driver],
            pendingWithdrawals[ride.passenger],
            block.timestamp
        );
    }

    // ─────────────────────────────────────────────────────────────
    // 👁️ VIEWS (leitura)
    // ─────────────────────────────────────────────────────────────

    // 🔎 retorna corrida completa
    function getRide(uint256 rideId) external view returns (Ride memory) {
        require(rides[rideId].id != 0, "Ride does not exist");
        return rides[rideId];
    }

    // 📍 retorna apenas coordenadas
    function getRideCoords(uint256 rideId)
        external
        view
        returns (
            string memory latOrigem,
            string memory lonOrigem,
            string memory latDestino,
            string memory lonDestino
        )
    {
        Ride storage ride = rides[rideId];
        require(ride.id != 0, "Ride does not exist");

        return (ride.latOrigem, ride.lonOrigem, ride.latDestino, ride.lonDestino);
    }

    // 💰 consulta saldo pendente
    function getPendingWithdrawal(address account)
        external
        view
        returns (uint256)
    {
        return pendingWithdrawals[account];
    }
}
