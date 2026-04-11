// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 🔐 Controle de acesso baseado em owner
import "@openzeppelin/contracts@4.9.3/access/Ownable.sol";

// 🛡 proteção contra reentrância
import "@openzeppelin/contracts@4.9.3/security/ReentrancyGuard.sol";

// 📦 interface do contrato externo de NFT dos motoristas
interface IDriverNFT {
    function mintDriverNFT(address driver, string calldata metadataCID) external returns (uint256);
    function revokeDriverNFT(address driver) external;
}

contract ViaChainGovernance is Ownable, ReentrancyGuard {

    // 🧠 referência ao contrato de NFT dos motoristas
    IDriverNFT public driverNFT;

    // 🏗 construtor recebe endereço do contrato NFT
    constructor(address nftAddress) {
        require(nftAddress != address(0), "Invalid NFT address");
        driverNFT = IDriverNFT(nftAddress);
    }

    // 📊 categorias possíveis do motorista
    enum Category {
        NONE,
        BASICO,
        CONFORTO,
        LUXO
    }

    // 📌 status do fluxo de aprovação
    enum DriverStatus {
        NONE,
        PENDING,
        APPROVED,
        REJECTED,
        REVOKED
    }

    // 🧾 estrutura completa do perfil do motorista
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

    // 🗂 storage principal dos perfis
    mapping(address => DriverProfile) private driverProfiles;

    // 📚 lista de todos os motoristas cadastrados
    address[] private allDrivers;

    // ⚡ controle para evitar duplicação na lista
    mapping(address => bool) private knownDriver;

    // 📡 eventos do sistema de governança
    event DriverRequested(address indexed driver);
    event DriverApproved(address indexed driver, Category category);
    event DriverRejected(address indexed driver);
    event DriverRevoked(address indexed driver);
    event DriverPriceUpdated(address indexed driver, uint256 newPrice);

    // 📝 motorista solicita registro no sistema
    function requestDriverRegistration(
        string calldata vehicleModel,
        string calldata vehiclePlate,
        string calldata vehicleCID
    ) external {

        // 🔎 validações básicas de entrada
        require(bytes(vehicleModel).length > 0, "Model required");
        require(bytes(vehiclePlate).length > 0, "Plate required");
        require(bytes(vehicleCID).length > 0, "CID required");

        // 📥 pega perfil atual (se existir)
        DriverProfile storage profile = driverProfiles[msg.sender];

        // 🚫 impede múltiplos registros ativos simultâneos
        require(
            profile.status == DriverStatus.NONE ||
            profile.status == DriverStatus.REJECTED ||
            profile.status == DriverStatus.REVOKED,
            "Already requested"
        );

        // 🧱 cria/atualiza perfil como PENDENTE
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

        // 📌 adiciona à lista global se ainda não existir
        if (!knownDriver[msg.sender]) {
            knownDriver[msg.sender] = true;
            allDrivers.push(msg.sender);
        }

        // 📡 evento de solicitação
        emit DriverRequested(msg.sender);
    }

    // ✅ aprova motorista e emite NFT
    function approveDriver(address driver, Category category)
        external
        onlyOwner
        nonReentrant
    {
        require(category != Category.NONE, "Invalid category");

        DriverProfile storage profile = driverProfiles[driver];
        require(profile.status == DriverStatus.PENDING, "Not pending");

        // ✔️ atualiza status e categoria
        profile.status = DriverStatus.APPROVED;
        profile.category = category;

        // 🪙 mint do NFT de identidade do motorista
        driverNFT.mintDriverNFT(driver, profile.vehicleCID);

        emit DriverApproved(driver, category);
    }

    // ❌ rejeita motorista (sem NFT)
    function rejectDriver(address driver) external onlyOwner {
        DriverProfile storage profile = driverProfiles[driver];
        require(profile.status == DriverStatus.PENDING, "Not pending");

        profile.status = DriverStatus.REJECTED;

        emit DriverRejected(driver);
    }

    // 🔥 revoga motorista e queima NFT
    function revokeDriver(address driver)
        external
        onlyOwner
        nonReentrant
    {
        DriverProfile storage profile = driverProfiles[driver];
        require(profile.status == DriverStatus.APPROVED, "Not approved");

        // 🚫 remove acesso do motorista
        profile.status = DriverStatus.REVOKED;
        profile.category = Category.NONE;
        profile.pricePerKmWei = 0;

        // 🔥 queima NFT associado
        driverNFT.revokeDriverNFT(driver);

        emit DriverRevoked(driver);
    }

    // 💰 motorista define seu preço por km
    function setMyPricePerKm(uint256 newPrice) external {
        require(newPrice > 0, "Invalid price");

        DriverProfile storage profile = driverProfiles[msg.sender];
        require(profile.status == DriverStatus.APPROVED, "Not approved");

        profile.pricePerKmWei = newPrice;

        emit DriverPriceUpdated(msg.sender, newPrice);
    }

    // 🔎 verifica se motorista está aprovado
    function isApprovedDriver(address driver) external view returns (bool) {
        return driverProfiles[driver].status == DriverStatus.APPROVED;
    }

    // 🔎 retorna categoria do motorista
    function getDriverCategory(address driver) external view returns (Category) {
        return driverProfiles[driver].category;
    }

    // 🔎 retorna preço por km
    function getDriverPrice(address driver) external view returns (uint256) {
        return driverProfiles[driver].pricePerKmWei;
    }

    // 📦 retorna perfil completo
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

    // 📚 lista todos os motoristas cadastrados
    function getAllDrivers() external view returns (address[] memory) {
        return allDrivers;
    }

    // ⏳ filtra motoristas pendentes
    function getPendingDrivers() external view returns (address[] memory) {
        uint256 count = 0;

        // 🔢 conta quantos estão pendentes
        for (uint256 i = 0; i < allDrivers.length; i++) {
            if (driverProfiles[allDrivers[i]].status == DriverStatus.PENDING) {
                count++;
            }
        }

        // 📦 cria array exato
        address[] memory pending = new address[](count);
        uint256 index = 0;

        // 🧱 preenche array
        for (uint256 i = 0; i < allDrivers.length; i++) {
            if (driverProfiles[allDrivers[i]].status == DriverStatus.PENDING) {
                pending[index++] = allDrivers[i];
            }
        }

        return pending;
    }

    // ✅ filtra motoristas aprovados
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

