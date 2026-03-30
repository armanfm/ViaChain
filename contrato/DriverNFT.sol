// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

//usar a bibilioteca do ERC721
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

// biblioteca que define quemn é o dono do contrato quando faz o deploy.
import "@openzeppelin/contracts/access/Ownable.sol";

// abertura do contrato que ja usa os imports.
contract DriverNFT is ERC721URIStorage, Ownable {

    //um atributo é para o id do token, apesar de unico.
    uint256 private _nextTokenId;

    // o outro atribto é a instacia da governaça que cria o token.
    address public governance;

    // aqui serve para mapear o token criado com o id do token, o endereço do motorista
    // e liga o token e o motorista;
    mapping(address => uint256) private driverToTokenId;
    mapping(uint256 => address) private tokenIdToDriver;

    // controla se o motorista já possui um NFT ativo
    mapping(address => bool) public hasActiveNFT;

    //eventos para tela de log onde a governaça pode adicionar mais responsaveis pela governaça.
    event GovernanceUpdated(address indexed oldGovernance, address indexed newGovernance);

    // evento da mintagem de novo token.
    event DriverNFTMinted(address indexed driver, uint256 indexed tokenId, string tokenURI);

    // evento disparado quando o NFT é revogado
    event DriverNFTRevoked(address indexed driver, uint256 indexed tokenId);

    // o construtor executa uma unica vez no deploy do contrato
    // inicializa o NFT (nome e simbolo)
    // define como owner o endereco que fez o deploy (msg.sender)
    // é importante dizer que o codigo não minta quando faz o deploy.
    // o mint ocorre depois via governança
    constructor() ERC721("ViaChain Driver NFT", "VCDNFT") Ownable(msg.sender) {}

    // a modifier serve para restringir, onde somente a governança pode fazer esta função
    // verifica se quem chamou (msg.sender) é igual ao endereço da governança
    modifier onlyGovernance() {
        require(msg.sender == governance, "Only governance can call");
        _;
    }

    // esta função define ou atualiza o endereço da governança
    // apenas quem fez o deploy (owner) pode executar
    function setGovernance(address _governance) external onlyOwner {
        require(_governance != address(0), "Invalid governance address");

        address oldGovernance = governance;
        governance = _governance;

        // emit manda o evento para o log da blockchain
        emit GovernanceUpdated(oldGovernance, _governance);
    }

    // esta função serve para minta o NFT
    // ela associa o NFT ao motorista e guarda o CID (link dos dados)
    function mintDriverNFT(address driver, string calldata metadataCID)
        external
        onlyGovernance
        returns (uint256)
    {
        // o require valida as condicoes obrigatorias da funcao
        // verifica o endereço se é valido, se tem NFT ja ativo, se possui cid
        require(driver != address(0), "Invalid driver");
        require(!hasActiveNFT[driver], "Driver already has active NFT");
        require(bytes(metadataCID).length > 0, "CID required");

        // se nao falhar cria um novo token
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

    // esta função revoga o NFT
    function revokeDriverNFT(address driver) external onlyGovernance {
        require(hasActiveNFT[driver], "Driver has no active NFT");

        uint256 tokenId = driverToTokenId[driver];

        _burn(tokenId);

        delete tokenIdToDriver[tokenId];
        delete driverToTokenId[driver];
        hasActiveNFT[driver] = false;

        emit DriverNFTRevoked(driver, tokenId);
    }

    // esta função retorna o tokenId do motorista
    // apenas funciona se ele tiver NFT ativo
    function getDriverTokenId(address driver) external view returns (uint256) {
        require(hasActiveNFT[driver], "Driver has no active NFT");
        return driverToTokenId[driver];
    }

    // esta função retorna o endereço do motorista a partir do tokenId
    function getDriverByTokenId(uint256 tokenId) external view returns (address) {
        return tokenIdToDriver[tokenId];
    }

    // esta função verifica se o motorista possui NFT ativo
    function hasNFT(address driver) external view returns (bool) {
        return hasActiveNFT[driver];
    }
}
