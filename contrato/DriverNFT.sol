// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 📦 Importa ERC721 com suporte a URI (metadata on-chain/off-chain)
import "@openzeppelin/contracts@4.9.3/token/ERC721/extensions/ERC721URIStorage.sol";

// 👤 Controle de dono do contrato (admin principal)
import "@openzeppelin/contracts@4.9.3/access/Ownable.sol";

// 🔐 Proteção contra reentrância (ataques em funções críticas)
import "@openzeppelin/contracts@4.9.3/security/ReentrancyGuard.sol";

contract DriverNFT is ERC721URIStorage, Ownable, ReentrancyGuard {

    // 🔢 contador incremental de tokens (ID único de cada NFT)
    uint256 private _nextTokenId;

    // 🏛 endereço de governança (quem pode mintar/revogar NFTs)
    address public governance;

    // 🧠 mapeia motorista => tokenId
    mapping(address => uint256) private driverToTokenId;

    // 🧠 mapeia tokenId => motorista
    mapping(uint256 => address) private tokenIdToDriver;

    // ⚡ controle rápido se o motorista já tem NFT ativo
    mapping(address => bool) public hasActiveNFT;

    // 📡 eventos para rastreamento on-chain
    event GovernanceUpdated(address indexed oldGovernance, address indexed newGovernance);
    event DriverNFTMinted(address indexed driver, uint256 indexed tokenId, string tokenURI);
    event DriverNFTRevoked(address indexed driver, uint256 indexed tokenId);

    // 🏗 construtor define nome e símbolo do NFT
    constructor() ERC721("ViaChain Driver NFT", "VCDNFT") {}

    // 🔒 limita funções apenas à governança
    modifier onlyGovernance() {
        require(msg.sender == governance, "Only governance");
        _;
    }

    // ⚙️ define ou troca endereço da governança (apenas owner do contrato)
    function setGovernance(address _governance) external onlyOwner {
        require(_governance != address(0), "Invalid address");

        address oldGovernance = governance;
        governance = _governance;

        emit GovernanceUpdated(oldGovernance, _governance);
    }

    // 🎯 cria (mint) um NFT para um motorista
    function mintDriverNFT(address driver, string calldata metadataCID)
        external
        onlyGovernance
        nonReentrant
        returns (uint256)
    {
        require(driver != address(0), "Invalid driver");
        require(!hasActiveNFT[driver], "Already has NFT");
        require(bytes(metadataCID).length > 0, "CID required");

        // 🆔 gera novo tokenId
        uint256 tokenId = _nextTokenId;
        _nextTokenId++;

        // 🧠 atualiza estado ANTES da interação externa (boa prática anti-reentrância)
        driverToTokenId[driver] = tokenId;
        tokenIdToDriver[tokenId] = driver;
        hasActiveNFT[driver] = true;

        // 🪙 cria NFT e atribui ao driver
        _safeMint(driver, tokenId);

        // 📎 define metadata (IPFS CID ou URL)
        _setTokenURI(tokenId, metadataCID);

        // 📡 evento de criação
        emit DriverNFTMinted(driver, tokenId, metadataCID);

        return tokenId;
    }

    // ❌ revoga (queima) o NFT do motorista
    function revokeDriverNFT(address driver) external onlyGovernance {
        require(hasActiveNFT[driver], "No NFT");

        uint256 tokenId = driverToTokenId[driver];

        // 🔥 destrói o NFT
        _burn(tokenId);

        // 🧹 limpa armazenamento
        delete tokenIdToDriver[tokenId];
        delete driverToTokenId[driver];
        hasActiveNFT[driver] = false;

        // 📡 evento de revogação
        emit DriverNFTRevoked(driver, tokenId);
    }

    // 🔎 retorna tokenId de um motorista
    function getDriverTokenId(address driver) external view returns (uint256) {
        require(hasActiveNFT[driver], "No NFT");
        return driverToTokenId[driver];
    }

    // 🔎 retorna dono (driver) de um tokenId
    function getDriverByTokenId(uint256 tokenId) external view returns (address) {
        return tokenIdToDriver[tokenId];
    }

    // 🔎 verifica se motorista possui NFT ativo
    function hasNFT(address driver) external view returns (bool) {
        return hasActiveNFT[driver];
    }

    // 🔒 impede transferência (NFT soulbound = não transferível)
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    )
        internal
        override
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);

        // 🚫 só permite mint (from = 0) e burn (to = 0)
        require(from == address(0) || to == address(0), "Transfer not allowed");
    }
}
