# 🗺️ ViaChain — Roadmap de Melhorias

> Protocolo Descentralizado de Corridas — Evoluções planejadas após o MVP

---

## ✅ O que está implementado (MVP)

- Registro e aprovação de motoristas via governança permissionada
- Credencial NFT (ERC-721) com categoria (básico / confort / luxo)
- Escrow de pagamento em ETH com confirmação dupla
- Timeout de 5 minutos para liberação automática
- Cancelamento com reembolso total antes do início
- Cancelamento proporcional após início via systemOperator (contrato preparado)
- Integração com oráculo Chainlink (ETH/BRL)
- Frontend Web3 com ethers.js + MetaMask
- Deploy na Sepolia testnet

---

## 🔜 Melhorias Planejadas

### 1. Stake ativado no aceite da corrida

**Situação atual:**
O stake do motorista é um depósito de entrada no sistema, sem vínculo direto com cada corrida. O motorista já paga gas ao aceitar — o que funciona como desincentivo básico ao abandono no MVP.

**Melhoria:**
Bloquear automaticamente parte do stake no momento do `acceptRide` — quando o motorista assume o compromisso real de buscar o passageiro.

**Impacto:**
Se o motorista aceitar e não comparecer, parte do stake é transferida ao passageiro como compensação. Abandono de corrida se torna financeiramente desvantajoso.

```solidity
function acceptRide(uint256 rideId) external payable {
    require(msg.value == STAKE_PER_RIDE, "Stake required");
    ride.driverStake = msg.value;
    ride.status = RideStatus.ACCEPTED;
}
```

---

### 2. Privacidade do destino do passageiro

**Situação atual:**
Origem e destino ficam no `localStorage` do frontend. Todos os motoristas veem as corridas disponíveis com destino para poder aceitar — isso é correto. O problema é que um passageiro poderia ver o destino de outro passageiro.

**Melhoria:**
- Motoristas veem corridas disponíveis com destino via API autenticada
- Passageiro A nunca vê o destino do Passageiro B
- Blockchain recebe apenas `valor + hash` — destino não fica exposto publicamente

**Arquitetura:**
```
Corrida criada → origem e destino ficam em backend privado
Motorista logado → vê corridas disponíveis com destino via API autenticada
Passageiro → nunca acessa dados de outros passageiros
Blockchain → só armazena valor + hash de integridade
```

---

### 3. Confirmação de presença física do motorista

**Situação atual:**
O `startRide` pode ser chamado pelo passageiro de qualquer lugar, sem validar se o motorista realmente chegou ao local de embarque.

**Melhoria:**
Validar via GPS off-chain que motorista e passageiro estão no mesmo raio geográfico antes de liberar o `startRide`. A confirmação de presença seria feita pelo backend e assinada antes de enviar ao contrato.

---

### 4. Otimização de gas — Remoção de loops em arrays

**Situação atual:**
As funções `getPendingDrivers` e `getApprovedDrivers` do `ViaChainGovernance` percorrem todo o array `allDrivers` a cada chamada. Se o protocolo crescer para 10.000 motoristas, essas funções falharão por exceder o Block Gas Limit da rede — o que é conhecido como "bomba de gas".

**Melhoria:**
Manter arrays separados por status (`pendingDrivers`, `approvedDrivers`) atualizados a cada mudança de estado, eliminando a necessidade de loops. Alternativamente, delegar a filtragem ao frontend ou a um indexador descentralizado como **The Graph**.

```solidity
// Em vez de filtrar no contrato:
mapping(address => DriverStatus) public driverStatus;
address[] public approvedDrivers; // atualizado no approve/revoke
```

---

### 5. Disponibilidade do motorista em tempo real

**Situação atual:**
O sistema não sabe se o motorista está online antes da corrida ser criada. Passageiros podem criar corridas para motoristas offline.

**Melhoria:**
Camada off-chain de presença em tempo real — motorista sinaliza disponibilidade no app. O frontend filtra apenas motoristas ativos antes de exibir a lista, evitando corridas sem resposta.

---

### 6. Governança descentralizada (DAO)

**Situação atual:**
Aprovação de motoristas depende de um administrador central (owner). Ponto único de controle identificado na auditoria.

**Melhoria:**
Evoluir para DAO com votação distribuída entre participantes do protocolo. Decisões como aprovação, revogação e alteração de parâmetros passariam por votação on-chain.

```
Admin central → DAO com quórum mínimo
Aprovação unilateral → Votação distribuída
```

---

### 7. Token ERC-20 nativo de recompensa

**Situação atual:**
Pagamentos e incentivos operam exclusivamente em ETH.

**Melhoria:**
Introduzir token nativo ERC-20 para recompensas por corridas concluídas, programa de fidelidade e participação na governança futura.

---

### 8. Oráculo de rota para validação de distância

**Situação atual:**
Distância é calculada off-chain e o contrato confia no valor informado sem validação independente.

**Melhoria:**
Integrar oráculo de rota descentralizado para validar que a distância declarada é compatível com a rota real entre origem e destino, reduzindo possibilidade de fraude no cálculo.

---

### 9. Cancelamento proporcional com GPS em tempo real

**Situação atual:**
O cancelamento após início da corrida devolve o valor integral ao passageiro. O contrato já possui a função `cancelAfterStartWithRecalculation` preparada para receber o valor proporcional calculado externamente, mas sem integração GPS o comportamento padrão é reembolso total.

**Melhoria:**
Integrar Google Maps API para rastrear a posição do motorista em tempo real. Com GPS ativo, o sistema evolui em duas frentes:

**Confirmações automáticas:**
```
GPS detecta motorista no local do passageiro → startRide automático
GPS detecta motorista no destino → confirmDestination automático
```
Elimina a necessidade de confirmação manual do motorista — mais seguro e sem possibilidade de fraude.

**Cancelamento simétrico e proporcional:**
```
Passageiro cancela no meio → sistema avisa motorista
                           → calcula distância percorrida
                           → motorista recebe proporcional
                           → passageiro recebe restante

Motorista cancela no meio → sistema avisa passageiro
                          → calcula distância percorrida
                          → motorista recebe proporcional
                          → passageiro recebe restante
```

Ambos os lados têm o mesmo direito ao cancelamento proporcional — com notificação automática para a parte afetada.

**Por que não foi implementado no MVP:**
A Google Maps API é paga em produção e requer movimento físico real para testes. O contrato já está preparado via `cancelAfterStartWithRecalculation` — falta apenas a camada off-chain de GPS.

---

## 📊 Priorização

| Melhoria | Impacto | Complexidade | Prioridade |
|---|---|---|---|
| Stake no aceite | Alto | Baixa | Alta |
| Privacidade do destino | Alto | Média | Alta |
| Otimização de gas (loops) | Alto | Baixa | Alta |
| Cancelamento proporcional GPS | Alto | Média | Alta |
| Confirmação de presença | Médio | Média | Média |
| Disponibilidade em tempo real | Médio | Média | Média |
| Governança DAO | Alto | Alta | Futura |
| Token ERC-20 nativo | Médio | Média | Futura |
| Oráculo de rota | Alto | Alta | Futura |

---

## 🏗️ Arquitetura alvo (pós-MVP)

```
Frontend Web3
HTML + ethers.js + MetaMask
        |
Backend Privado
Destinos · Disponibilidade · GPS em tempo real
        |
Blockchain (Sepolia)
DriverNFT · Governance · Escrow
Stake por corrida · DAO · Token
```

---

*ViaChain MVP — Armando Freire 2026*


