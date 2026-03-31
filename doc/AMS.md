# 📝 Nota Técnica — Conexões Arquiteturais do ViaChain AMS (Automated Market Service)

## 1. Similaridade com AMM (Automated Market Maker)

### O modelo AMM clássico

Protocolos como Uniswap v3 utilizam NFTs de posição de liquidez. Quando um provedor deposita tokens no pool, recebe um NFT que representa:
- Sua participação no pool
- Seus direitos de retirada
- Sua identidade dentro do protocolo

Esse NFT não é transferível livremente pois representa um compromisso ativo com o protocolo.

### O modelo ViaChain

O DriverNFT segue a mesma lógica aplicada ao transporte descentralizado:

| AMM (Uniswap v3) | ViaChain |
|---|---|
| Deposita liquidez | Deposita stake em ETH |
| Recebe NFT de posição | Recebe NFT de credencial |
| NFT representa direitos no pool | NFT representa direitos no protocolo |
| Revogado ao retirar liquidez | Revogado ao sair ou fraudar |
| Não transferível livremente | Não transferível |

### A diferença conceitual importante

No AMM o NFT é **financeiro** — representa tokens e posição de liquidez.

No ViaChain o NFT é de **identidade** — representa uma pessoa verificada, sua categoria e seu histórico on-chain. Isso é mais sofisticado porque combina DeFi com identidade descentralizada.

### Precificação por demanda (Fase 2)

O leilão reverso da Fase 2 vai além — aplica a lógica de precificação do AMM ao transporte:

```
AMM:     x * y = k  →  preço emerge do equilíbrio oferta/demanda
ViaChain: passageiro propõe → motoristas aceitam ou não → preço emerge do mercado
```

- Poucos motoristas disponíveis → passageiro precisa oferecer mais
- Muitos motoristas disponíveis → passageiro pode oferecer menos

O preço não é definido por ninguém — emerge automaticamente do equilíbrio entre oferta de motoristas e demanda de passageiros. É um **AMM de transporte**.

---

## 2. Identidade Descentralizada (DID — Decentralized Identity)

### O problema que o ViaChain resolve

Sistemas tradicionais de KYC (Know Your Customer) armazenam dados de identidade em bancos de dados centralizados. O usuário não controla seus próprios dados e precisa se verificar novamente em cada plataforma.

### O modelo ViaChain

O DriverNFT implementa um modelo de **KYC descentralizado**:

1. Verificação de identidade acontece uma vez pelo admin
2. Resultado gravado on-chain como NFT
3. Qualquer contrato do ecossistema pode verificar `hasNFT()` sem banco de dados central
4. Identidade é portátil — outros protocolos poderiam aceitar o mesmo NFT como prova de motorista verificado

### Comparação com projetos de DID

| Projeto | Abordagem | ViaChain |
|---|---|---|
| Worldcoin | Prova de humanidade via biometria | Prova de identidade via admin |
| Civic | Verificação KYC off-chain + token | Verificação KYC off-chain + NFT |
| ENS | Nome on-chain como identidade | Credencial on-chain como identidade |

O ViaChain chega numa solução simples e funcional para um caso de uso específico — sem a complexidade dos projetos genéricos de DID.

### Evolução na Fase 2

Com a DAO e o token $VIA, o NFT de identidade vira também um **token de governança com peso**:

```
NFT de identidade verificada
        +
Histórico de corridas on-chain (Proof of Ride)
        +
Saldo de $VIA em staking
        =
Reputação on-chain portátil e auditável
```

Isso combina três conceitos avançados em um modelo coeso:
- **DeFi** — staking e tokenomics
- **DID** — identidade descentralizada verificada
- **Reputação on-chain** — histórico imutável e auditável

---

## 3. Posicionamento no Ecossistema Web3

O ViaChain não é apenas um app de transporte descentralizado. É um protocolo que resolve três problemas simultaneamente:

1. **Intermediação de pagamentos** — eliminada pelo escrow on-chain
2. **Verificação de identidade** — resolvida pelo DriverNFT (DID simplificado)
3. **Precificação justa** — resolvida pelo leilão reverso (AMM de transporte)

Cada um desses problemas tem projetos dedicados no ecossistema Web3. O ViaChain os resolve de forma integrada dentro de um caso de uso real e cotidiano.

---

*ViaChain MVP — Armando Freire
