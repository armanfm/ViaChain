# 🚀 ViaChain — Fase 2: Ecossistema Econômico

> Evolução do protocolo de pagamentos simples para uma economia circular completa

---

## Visão Geral

O ViaChain Fase 2 transforma o protocolo de um sistema de pagamentos diretos em ETH para um **ecossistema econômico circular**, onde o token nativo `$VIA` incentiva motoristas, empodera passageiros e alimenta a governança descentralizada.

---

## 1. Token Nativo $VIA (ERC-20)

O `$VIA` é o token de utilidade do protocolo — o motor que alimenta todas as interações entre usuários.

| Propriedade | Detalhe |
|---|---|
| Padrão | ERC-20 (OpenZeppelin) |
| Função | Moeda de troca, recompensas e staking de governança |
| Emissão | Controlada pelo contrato de Governança |
| Paridade | Oráculo Chainlink mantém preço ETH/$VIA justo |

---

## 2. Sistema de Ofertas do Passageiro (Leilão Reverso)

Em vez de o motorista definir o preço, o **passageiro propõe o valor** que está disposto a pagar — invertendo a lógica do Uber tradicional.

**Como funciona:**

```
Passageiro publica corrida com trajeto + valor em $VIA
        ↓
Tokens $VIA bloqueados no RideEscrow
        ↓
Motoristas visualizam pool de ofertas
        ↓
Motorista aceita a oferta mais atrativa
        ↓
Sem aceite em X minutos → passageiro resgata tokens
```

**Vantagens:**
- Mercado mais eficiente — preço determinado pela demanda real
- Passageiro tem poder de negociação
- Motorista escolhe as corridas mais rentáveis

---

## 3. Proof of Ride — Metas e Recompensas

Sistema de bônus por produtividade para incentivar motoristas ativos.

**Marcos de recompensa:**

| Nível | Meta | Recompensa |
|---|---|---|
| Nível 1 | 10 corridas | Bônus em $VIA |
| Nível 2 | 50 corridas | Bônus maior + upgrade de categoria |
| Nível 3 | 200 corridas | Acesso à categoria Luxo + voto na DAO |

**Ajuste por oráculo:**
O valor do bônus é recalculado via Chainlink para manter valor real independente da volatilidade do mercado.

---

## 4. Staking para Upgrade de Categoria

Motoristas fazem staking de `$VIA` para subir de categoria e ganhar mais visibilidade no protocolo.

```
Básico → Confort → Luxo
  ↑           ↑        ↑
staking    staking   staking
  +           +        +
metas       metas    metas
```

**Benefícios do staking:**
- Acesso a categorias premium
- Peso de voto proporcional na DAO
- Reputação on-chain verificável

---

## 5. Fluxo da Economia Circular

```
1. Passageiro deposita ETH → recebe $VIA
2. Usa $VIA para contratar corridas
3. Motorista recebe $VIA pelo serviço
4. Protocolo emite $VIA para motoristas que batem metas
5. Motoristas fazem staking → sobem de categoria → participam da DAO
6. DAO decide emissão, parâmetros e upgrades do protocolo
```

---

## 6. Contratos Envolvidos na Fase 2

| Contrato | Função | Status |
|---|---|---|
| `ViaChainToken.sol` | ERC-20 — token $VIA | Novo |
| `RideEscrow.sol` | Atualizado para aceitar tokens via approve/transferFrom | Atualizar |
| `ViaChainGovernance.sol` | Lógica de metas, câmbio ETH/$VIA e DAO por token | Atualizar |

**Segurança:**
Todas as transferências de tokens no Escrow seguirão o padrão `approve` + `transferFrom`, mantendo proteção `nonReentrant` em todas as funções críticas.

---

## 7. Alinhamento com Requisitos Técnicos

| Requisito | Implementação na Fase 2 |
|---|---|
| Token ERC-20 | Token $VIA como centro da economia |
| Staking com recompensa | Bloqueio de tokens + bônus por metas de corridas |
| Integração com oráculo | Preço do token e ajuste de recompensas via Chainlink |
| Governança DAO | Peso de voto proporcional ao saldo de $VIA + reputação |

---

*ViaChain é um protocolo financeiro completo focado em autonomia e incentivos programáveis.*

*Armando José Freire de Melo | Turma 1 | 2026*
