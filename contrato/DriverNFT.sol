// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DriverNFT is ERC721URIStorage, Ownable {
    uint256 private _nextTokenId;
    address public governance;

    mapping(address => uint256) private driverToTokenId;
    mapping(uint256 => address) private tokenIdToDriver;
    mapping(address => bool) public hasActiveNFT;

    event GovernanceUpdated(address indexed oldGovernance, address indexed newGovernance);
    event DriverNFTMinted(address indexed driver, uint256 indexed tokenId, string tokenURI);
    event DriverNFTRevoked(address indexed driver, uint256 indexed tokenId);

    constructor() ERC721("ViaChain Driver NFT", "VCDNFT") Ownable(msg.sender) {}

    modifier onlyGovernance() {
        require(msg.sender == governance, "Only governance can call");
        _;
    }

    function setGovernance(address _governance) external onlyOwner {
        require(_governance != address(0), "Invalid governance address");

        address oldGovernance = governance;
        governance = _governance;

        emit GovernanceUpdated(oldGovernance, _governance);
    }

    function mintDriverNFT(address driver, string calldata metadataCID)
        external
        onlyGovernance
        returns (uint256)
    {
        require(driver != address(0), "Invalid driver");
        require(!hasActiveNFT[driver], "Driver already has active NFT");
        require(bytes(metadataCID).length > 0, "CID required");

        uint256 tokenId = _nextTokenId;
        _nextTokenId++;

        _safeMint(driver, tokenId);
        _setTokenURI(tokenId, metadataCID);

        driverToTokenId[driver] = tokenId;
        tokenIdToDriver[tokenId] = driver;
        hasActiveNFT[driver] = true;

        emit DriverNFTMinted(driver, tokenId, metadataCID);

        return tokenId;
    }

    function revokeDriverNFT(address driver) external onlyGovernance {
        require(hasActiveNFT[driver], "Driver has no active NFT");

        uint256 tokenId = driverToTokenId[driver];

        _burn(tokenId);

        delete tokenIdToDriver[tokenId];
        delete driverToTokenId[driver];
        hasActiveNFT[driver] = false;

        emit DriverNFTRevoked(driver, tokenId);
    }

    function getDriverTokenId(address driver) external view returns (uint256) {
        require(hasActiveNFT[driver], "Driver has no active NFT");
        return driverToTokenId[driver];
    }

    function getDriverByTokenId(uint256 tokenId) external view returns (address) {
        return tokenIdToDriver[tokenId];
    }

    function hasNFT(address driver) external view returns (bool) {
        return hasActiveNFT[driver];
    }
}
