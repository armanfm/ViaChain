// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ✅ IMPORTS CORRETOS PARA REMIX
import "@openzeppelin/contracts@4.9.3/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts@4.9.3/access/Ownable.sol";
import "@openzeppelin/contracts@4.9.3/security/ReentrancyGuard.sol";

contract DriverNFT is ERC721URIStorage, Ownable, ReentrancyGuard {

    uint256 private _nextTokenId;
    address public governance;

    mapping(address => uint256) private driverToTokenId;
    mapping(uint256 => address) private tokenIdToDriver;
    mapping(address => bool) public hasActiveNFT;

    event GovernanceUpdated(address indexed oldGovernance, address indexed newGovernance);
    event DriverNFTMinted(address indexed driver, uint256 indexed tokenId, string tokenURI);
    event DriverNFTRevoked(address indexed driver, uint256 indexed tokenId);

    constructor() ERC721("ViaChain Driver NFT", "VCDNFT") {}

    modifier onlyGovernance() {
        require(msg.sender == governance, "Only governance");
        _;
    }

    function setGovernance(address _governance) external onlyOwner {
        require(_governance != address(0), "Invalid address");

        address oldGovernance = governance;
        governance = _governance;

        emit GovernanceUpdated(oldGovernance, _governance);
    }

    function mintDriverNFT(address driver, string calldata metadataCID)
        external
        onlyGovernance
        nonReentrant
        returns (uint256)
    {
        require(driver != address(0), "Invalid driver");
        require(!hasActiveNFT[driver], "Already has NFT");
        require(bytes(metadataCID).length > 0, "CID required");

        uint256 tokenId = _nextTokenId;
        _nextTokenId++;

        // ✅ EFFECTS (corrige reentrancy)
        driverToTokenId[driver] = tokenId;
        tokenIdToDriver[tokenId] = driver;
        hasActiveNFT[driver] = true;

        // ❗ INTERAÇÃO EXTERNA
        _safeMint(driver, tokenId);
        _setTokenURI(tokenId, metadataCID);

        emit DriverNFTMinted(driver, tokenId, metadataCID);

        return tokenId;
    }

    function revokeDriverNFT(address driver) external onlyGovernance {
        require(hasActiveNFT[driver], "No NFT");

        uint256 tokenId = driverToTokenId[driver];

        _burn(tokenId);

        delete tokenIdToDriver[tokenId];
        delete driverToTokenId[driver];
        hasActiveNFT[driver] = false;

        emit DriverNFTRevoked(driver, tokenId);
    }

    function getDriverTokenId(address driver) external view returns (uint256) {
        require(hasActiveNFT[driver], "No NFT");
        return driverToTokenId[driver];
    }

    function getDriverByTokenId(uint256 tokenId) external view returns (address) {
        return tokenIdToDriver[tokenId];
    }

    function hasNFT(address driver) external view returns (bool) {
        return hasActiveNFT[driver];
    }

    // 🔒 SOULBOUND (não pode transferir)
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        require(from == address(0) || to == address(0), "Transfer not allowed");
    }
}

