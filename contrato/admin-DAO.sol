
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts@4.9.3/access/Ownable.sol";
import "@openzeppelin/contracts@4.9.3/security/ReentrancyGuard.sol";

interface IDriverNFT {
    function mintDriverNFT(address driver, string calldata metadataCID) external returns (uint256);
    function revokeDriverNFT(address driver) external;
}

contract ViaChainGovernance is Ownable, ReentrancyGuard {

    IDriverNFT public driverNFT;

    // ✅ CORRIGIDO: removido Ownable(msg.sender)
    constructor(address nftAddress) {
        require(nftAddress != address(0), "Invalid NFT address");
        driverNFT = IDriverNFT(nftAddress);
    }

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

    struct DriverProfile {
        address driver;
        string vehicleModel;
        string vehiclePlate;
        string vehicleCID;
        uint256 requestedAt;
        DriverStatus status;
        Category category;
        uint256 pricePerKmWei;
    }

    mapping(address => DriverProfile) private driverProfiles;
    address[] private allDrivers;
    mapping(address => bool) private knownDriver;

    event DriverRequested(address indexed driver);
    event DriverApproved(address indexed driver, Category category);
    event DriverRejected(address indexed driver);
    event DriverRevoked(address indexed driver);
    event DriverPriceUpdated(address indexed driver, uint256 newPrice);

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
            "Already requested"
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

        if (!knownDriver[msg.sender]) {
            knownDriver[msg.sender] = true;
            allDrivers.push(msg.sender);
        }

        emit DriverRequested(msg.sender);
    }

    // 🔒 proteção extra contra reentrancy
    function approveDriver(address driver, Category category)
        external
        onlyOwner
        nonReentrant
    {
        require(category != Category.NONE, "Invalid category");

        DriverProfile storage profile = driverProfiles[driver];
        require(profile.status == DriverStatus.PENDING, "Not pending");

        profile.status = DriverStatus.APPROVED;
        profile.category = category;

        driverNFT.mintDriverNFT(driver, profile.vehicleCID);

        emit DriverApproved(driver, category);
    }

    function rejectDriver(address driver) external onlyOwner {
        DriverProfile storage profile = driverProfiles[driver];
        require(profile.status == DriverStatus.PENDING, "Not pending");

        profile.status = DriverStatus.REJECTED;

        emit DriverRejected(driver);
    }

    // 🔒 proteção extra contra reentrancy
    function revokeDriver(address driver)
        external
        onlyOwner
        nonReentrant
    {
        DriverProfile storage profile = driverProfiles[driver];
        require(profile.status == DriverStatus.APPROVED, "Not approved");

        profile.status = DriverStatus.REVOKED;
        profile.category = Category.NONE;
        profile.pricePerKmWei = 0;

        driverNFT.revokeDriverNFT(driver);

        emit DriverRevoked(driver);
    }

    function setMyPricePerKm(uint256 newPrice) external {
        require(newPrice > 0, "Invalid price");

        DriverProfile storage profile = driverProfiles[msg.sender];
        require(profile.status == DriverStatus.APPROVED, "Not approved");

        profile.pricePerKmWei = newPrice;

        emit DriverPriceUpdated(msg.sender, newPrice);
    }

    function isApprovedDriver(address driver) external view returns (bool) {
        return driverProfiles[driver].status == DriverStatus.APPROVED;
    }

    function getDriverCategory(address driver) external view returns (Category) {
        return driverProfiles[driver].category;
    }

    function getDriverPrice(address driver) external view returns (uint256) {
        return driverProfiles[driver].pricePerKmWei;
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

    function getAllDrivers() external view returns (address[] memory) {
        return allDrivers;
    }

    function getPendingDrivers() external view returns (address[] memory) {
        uint256 count = 0;

        for (uint256 i = 0; i < allDrivers.length; i++) {
            if (driverProfiles[allDrivers[i]].status == DriverStatus.PENDING) {
                count++;
            }
        }

        address[] memory pending = new address[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < allDrivers.length; i++) {
            if (driverProfiles[allDrivers[i]].status == DriverStatus.PENDING) {
                pending[index++] = allDrivers[i];
            }
        }

        return pending;
    }

    function getApprovedDrivers() external view returns (address[] memory) {
        uint256 count = 0;

        for (uint256 i = 0; i < allDrivers.length; i++) {
            if (driverProfiles[allDrivers[i]].status == DriverStatus.APPROVED) {
                count++;
            }
        }

        address[] memory approved = new address[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < allDrivers.length; i++) {
            if (driverProfiles[allDrivers[i]].status == DriverStatus.APPROVED) {
                approved[index++] = allDrivers[i];
            }
        }

        return approved;
    }
}


