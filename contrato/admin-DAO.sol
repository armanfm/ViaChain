// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract ViaChainGovernance is Ownable {

    constructor() Ownable(msg.sender) {}

    // ================= ENUMS =================

    enum Category {
        NONE,
        BASICO,
        CONFORTO,
        LUXO
    }

    enum DriverStatus {
        NONE,
        PENDING,
        APPROVED,
        REJECTED,
        REVOKED
    }

    // ================= STRUCT =================

    struct DriverProfile {
        address driver;
        string vehicleModel;
        string vehiclePlate;
        string vehicleCID; // IPFS
        uint256 requestedAt;
        DriverStatus status;
        Category category;
        uint256 pricePerKmWei;
    }

    // ================= STORAGE =================

    mapping(address => DriverProfile) private driverProfiles;

    // ================= EVENTS =================

    event DriverRequested(
        address indexed driver,
        string vehicleModel,
        string vehiclePlate,
        uint256 timestamp
    );

    event DriverApproved(
        address indexed driver,
        Category category,
        uint256 timestamp
    );

    event DriverRejected(address indexed driver, uint256 timestamp);

    event DriverRevoked(address indexed driver, uint256 timestamp);

    event DriverPriceUpdated(
        address indexed driver,
        uint256 oldPrice,
        uint256 newPrice
    );

    // ================= REQUEST =================

    function requestDriverRegistration(
        string calldata vehicleModel,
        string calldata vehiclePlate,
        string calldata vehicleCID
    ) external {
        require(bytes(vehicleModel).length > 0, "Model required");
        require(bytes(vehiclePlate).length > 0, "Plate required");
        require(bytes(vehicleCID).length > 0, "CID required");

        DriverProfile storage profile = driverProfiles[msg.sender];

        require(
            profile.status == DriverStatus.NONE ||
            profile.status == DriverStatus.REJECTED ||
            profile.status == DriverStatus.REVOKED,
            "Already requested or active"
        );

        driverProfiles[msg.sender] = DriverProfile({
            driver: msg.sender,
            vehicleModel: vehicleModel,
            vehiclePlate: vehiclePlate,
            vehicleCID: vehicleCID,
            requestedAt: block.timestamp,
            status: DriverStatus.PENDING,
            category: Category.NONE,
            pricePerKmWei: 0
        });

        emit DriverRequested(
            msg.sender,
            vehicleModel,
            vehiclePlate,
            block.timestamp
        );
    }

    // ================= APPROVAL =================

    function approveDriver(address driver, Category category) external onlyOwner {
        require(driver != address(0), "Invalid driver");
        require(category != Category.NONE, "Invalid category");

        DriverProfile storage profile = driverProfiles[driver];
        require(profile.status == DriverStatus.PENDING, "Not pending");

        profile.status = DriverStatus.APPROVED;
        profile.category = category;

        emit DriverApproved(driver, category, block.timestamp);
    }

    function rejectDriver(address driver) external onlyOwner {
        require(driver != address(0), "Invalid driver");

        DriverProfile storage profile = driverProfiles[driver];
        require(profile.status == DriverStatus.PENDING, "Not pending");

        profile.status = DriverStatus.REJECTED;
        profile.category = Category.NONE;

        emit DriverRejected(driver, block.timestamp);
    }

    function revokeDriver(address driver) external onlyOwner {
        require(driver != address(0), "Invalid driver");

        DriverProfile storage profile = driverProfiles[driver];
        require(profile.status == DriverStatus.APPROVED, "Not approved");

        profile.status = DriverStatus.REVOKED;
        profile.category = Category.NONE;
        profile.pricePerKmWei = 0;

        emit DriverRevoked(driver, block.timestamp);
    }

    // ================= DRIVER ACTION =================

    function setMyPricePerKm(uint256 newPrice) external {
        require(newPrice > 0, "Invalid price");

        DriverProfile storage profile = driverProfiles[msg.sender];
        require(profile.status == DriverStatus.APPROVED, "Not approved");

        uint256 oldPrice = profile.pricePerKmWei;
        profile.pricePerKmWei = newPrice;

        emit DriverPriceUpdated(msg.sender, oldPrice, newPrice);
    }

    // ================= GETTERS =================

    function isApprovedDriver(address driver) external view returns (bool) {
        return driverProfiles[driver].status == DriverStatus.APPROVED;
    }

    function getDriverCategory(address driver) external view returns (Category) {
        return driverProfiles[driver].category;
    }

    function getDriverPrice(address driver) external view returns (uint256) {
        return driverProfiles[driver].pricePerKmWei;
    }

    function getVehicleCID(address driver) external view returns (string memory) {
        return driverProfiles[driver].vehicleCID;
    }

    function getDriverProfile(address driver)
        external
        view
        returns (
            address,
            string memory,
            string memory,
            string memory,
            uint256,
            DriverStatus,
            Category,
            uint256
        )
    {
        DriverProfile memory p = driverProfiles[driver];

        return (
            p.driver,
            p.vehicleModel,
            p.vehiclePlate,
            p.vehicleCID,
            p.requestedAt,
            p.status,
            p.category,
            p.pricePerKmWei
        );
    }
}
