// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IGovernance {
    function isApprovedDriver(address driver) external view returns (bool);
    function getDriverPrice(address driver) external view returns (uint256);
}

contract RideEscrow is ReentrancyGuard, Ownable {
    IGovernance public governance;

    uint256 public rideCounter;
    uint256 public constant PASSENGER_CONFIRMATION_TIMEOUT = 5 minutes;

    address public systemOperator;

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

    event SystemOperatorUpdated(address indexed oldOperator, address indexed newOperator);

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

    event RideCancelledAfterStart(
        uint256 indexed rideId,
        address indexed executor,
        uint256 paidToDriverWei,
        uint256 refundedToPassengerWei,
        uint256 cancelledAt
    );

    modifier onlySystemOperator() {
        require(
            msg.sender == systemOperator || msg.sender == owner(),
            "Not system operator"
        );
        _;
    }

    constructor(address governanceAddress) Ownable(msg.sender) {
        require(governanceAddress != address(0), "Invalid governance address");
        governance = IGovernance(governanceAddress);
    }

    function setSystemOperator(address newOperator) external onlyOwner {
        address oldOperator = systemOperator;
        systemOperator = newOperator;
        emit SystemOperatorUpdated(oldOperator, newOperator);
    }

    function createRide(address driver) external payable returns (uint256) {
        require(driver != address(0), "Invalid driver");
        require(governance.isApprovedDriver(driver), "Driver not approved");
        require(msg.value > 0, "Must send ETH");

        rideCounter++;

        rides[rideCounter] = Ride({
            id: rideCounter,
            passenger: msg.sender,
            driver: driver,
            quotedPriceWei: msg.value,
            createdAt: block.timestamp,
            acceptedAt: 0,
            startedAt: 0,
            driverConfirmedDestinationAt: 0,
            completedAt: 0,
            status: RideStatus.CREATED
        });

        emit RideCreated(
            rideCounter,
            msg.sender,
            driver,
            msg.value,
            block.timestamp
        );

        return rideCounter;
    }

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

    function rejectRide(uint256 rideId) external nonReentrant {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(msg.sender == ride.driver, "Only driver can reject");
        require(ride.status == RideStatus.CREATED, "Invalid ride state");

        ride.status = RideStatus.DRIVER_REJECTED;
        uint256 amount = ride.quotedPriceWei;
        ride.quotedPriceWei = 0;

        (bool success, ) = payable(ride.passenger).call{value: amount}("");
        require(success, "Refund failed");

        emit RideRejected(rideId, msg.sender, amount, block.timestamp);
    }

    function cancelBeforeStart(uint256 rideId) external nonReentrant {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(msg.sender == ride.passenger, "Only passenger can cancel");
        require(
            ride.status == RideStatus.CREATED || ride.status == RideStatus.ACCEPTED,
            "Ride already started"
        );

        ride.status = RideStatus.CANCELLED;
        uint256 amount = ride.quotedPriceWei;
        ride.quotedPriceWei = 0;

        (bool success, ) = payable(ride.passenger).call{value: amount}("");
        require(success, "Refund failed");

        emit RideCancelledBeforeStart(
            rideId,
            msg.sender,
            amount,
            block.timestamp
        );
    }

    function startRide(uint256 rideId) external {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(msg.sender == ride.passenger, "Only passenger can start");
        require(ride.status == RideStatus.ACCEPTED, "Ride not accepted");

        ride.status = RideStatus.STARTED;
        ride.startedAt = block.timestamp;

        emit RideStarted(rideId, msg.sender, block.timestamp);
    }

    function confirmDestinationReached(uint256 rideId) external {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(msg.sender == ride.driver, "Only driver can confirm");
        require(ride.status == RideStatus.STARTED, "Ride not started");

        ride.status = RideStatus.DRIVER_CONFIRMED_DESTINATION;
        ride.driverConfirmedDestinationAt = block.timestamp;

        emit DestinationConfirmedByDriver(rideId, msg.sender, block.timestamp);
    }

    function confirmRideCompletion(uint256 rideId) external nonReentrant {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(msg.sender == ride.passenger, "Only passenger can confirm");
        require(
            ride.status == RideStatus.DRIVER_CONFIRMED_DESTINATION,
            "Destination not confirmed by driver"
        );

        uint256 amount = ride.quotedPriceWei;

        ride.status = RideStatus.COMPLETED;
        ride.completedAt = block.timestamp;
        ride.quotedPriceWei = 0;

        (bool success, ) = payable(ride.driver).call{value: amount}("");
        require(success, "Payment failed");

        emit RideCompleted(
            rideId,
            ride.passenger,
            ride.driver,
            amount,
            block.timestamp
        );
    }

    function finalizeAfterTimeout(uint256 rideId) external nonReentrant {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(
            ride.status == RideStatus.DRIVER_CONFIRMED_DESTINATION,
            "Timeout not available"
        );
        require(
            block.timestamp >=
                ride.driverConfirmedDestinationAt + PASSENGER_CONFIRMATION_TIMEOUT,
            "Timeout not reached"
        );

        uint256 amount = ride.quotedPriceWei;

        ride.status = RideStatus.COMPLETED;
        ride.completedAt = block.timestamp;
        ride.quotedPriceWei = 0;

        (bool success, ) = payable(ride.driver).call{value: amount}("");
        require(success, "Payment failed");

        emit RideCompletedByTimeout(
            rideId,
            msg.sender,
            ride.driver,
            amount,
            block.timestamp
        );
    }

    function cancelAfterStartWithRecalculation(
        uint256 rideId,
        uint256 driverAmountWei
    ) external nonReentrant onlySystemOperator {
        Ride storage ride = rides[rideId];

        require(ride.id != 0, "Ride does not exist");
        require(
            ride.status == RideStatus.STARTED ||
                ride.status == RideStatus.DRIVER_CONFIRMED_DESTINATION,
            "Ride not eligible"
        );
        require(driverAmountWei <= ride.quotedPriceWei, "Invalid recalculated amount");

        uint256 passengerRefundWei = ride.quotedPriceWei - driverAmountWei;

        ride.status = RideStatus.CANCELLED;
        ride.completedAt = block.timestamp;
        ride.quotedPriceWei = 0;

        if (driverAmountWei > 0) {
            (bool driverPaid, ) = payable(ride.driver).call{value: driverAmountWei}("");
            require(driverPaid, "Driver payment failed");
        }

        if (passengerRefundWei > 0) {
            (bool passengerRefunded, ) = payable(ride.passenger).call{value: passengerRefundWei}("");
            require(passengerRefunded, "Passenger refund failed");
        }

        emit RideCancelledAfterStart(
            rideId,
            msg.sender,
            driverAmountWei,
            passengerRefundWei,
            block.timestamp
        );
    }

    function getRide(uint256 rideId) external view returns (Ride memory) {
        require(rides[rideId].id != 0, "Ride does not exist");
        return rides[rideId];
    }
}
