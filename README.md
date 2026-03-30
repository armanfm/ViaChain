# 🚗 ViaChain — Protocolo Descentralizado de Corridas

## 📌 Descrição

O **ViaChain** é um protocolo descentralizado para gerenciamento de corridas, onde:

- pagamentos são realizados diretamente em **ETH**
- motoristas são registrados por meio de **NFT (ERC-721)**
- cada motorista define seu próprio preço por quilômetro
- não há intermediários controlando o sistema

---

## 🚨 Problema

Plataformas centralizadas de transporte:

- controlam preços  
- validam motoristas de forma opaca  
- retêm taxas  
- concentram poder  

---

## 💡 Solução

O ViaChain propõe:

- uso de **smart contracts** para execução das regras  
- validação de motoristas via **NFT**  
- pagamentos diretos em blockchain  
- transparência e auditabilidade  

---

## 🧠 Arquitetura do Sistema

### Componentes

- 👤 **Passageiro** → solicita corrida e paga em ETH  
- 🚗 **Motorista** → define preço/km e opera com NFT  
- 🧠 **Governança** → aprova motoristas e emite NFT  
- 📜 **Smart Contracts** → executam regras e pagamentos  
- 🌐 **Oráculo** → fornece cotação ETH/BRL  

---

## 🔐 Credencial NFT (DriverNFT)

Cada motorista aprovado recebe um NFT que representa:

- autorização para operar  
- identidade no sistema  
- categoria do veículo  

### Regras

- apenas 1 NFT por motorista  
- não transferível  
- pode ser revogado pela governança  

---

## ⚙️ Funcionalidades

### 🟢 Mint de NFT
- executado apenas pela governança  
- vincula motorista ao sistema  

### 🔴 Revogação de NFT
- remove autorização do motorista  
- impede novas corridas  

### 🔍 Consultas
- verificar se motorista possui NFT  
- obter tokenId  
- obter motorista pelo token  

---

## 💰 Pagamentos (Escrow)

- passageiro deposita ETH antes da corrida  
- contrato mantém o valor bloqueado  
- pagamento liberado após confirmação  

---

## 📈 Modelo de Mercado

- motoristas definem preço por km  
- passageiros escolhem livremente  
- competição descentralizada  

---

## 🔄 Fluxo da Corrida

1. passageiro filtra por categoria  
2. escolhe motorista  
3. sistema calcula valor off-chain  
4. passageiro deposita ETH  
5. motorista aceita corrida  
6. passageiro confirma embarque  
7. motorista finaliza corrida  
8. pagamento é liberado  

---

## 🧩 Tecnologias Utilizadas

- Solidity ^0.8.20  
- ERC-721 (NFT)  
- OpenZeppelin  
- Chainlink (oráculo)  

---

## 🔐 Segurança

- controle por governança  
- validação via NFT  
- staking como garantia  
- execução automática via smart contracts  

---

## 📌 Considerações

Este projeto é um **MVP (Minimum Viable Product)** com:

- governança centralizada (temporária)  
- mercado descentralizado  
- reputação off-chain  

---

## 👨‍💻 Autor

**Armando Freire**
