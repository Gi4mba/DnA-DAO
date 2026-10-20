# DnA-DAO

[English](#english) · [Italiano](#italiano)

---

## English

Token-based DAO for DnA's science and tech community: members vote on governance proposals through a direct-democracy Ethereum smart contract. Foundry / Solidity project.

### How it works

The `GovernanceDAO` contract has two separate, irreversible phases.

1. **Sales.** Anyone buys shares by paying with an ERC-20 token (`buyShares`). Proposing and voting are not available yet.
2. **Governance.** After `closeSales()` (owner only) no more shares can be bought. Shareholders create proposals and vote. Total shares are fixed, so no snapshot is needed.

Decisions are only a record (text, aggregated votes, outcome): the contract executes nothing on-chain.

#### Rules

- **Price:** `exchangeRate` shares per token, whole shares rounded down. Only the cost of the shares actually obtained is collected (rounded up); the remainder stays with the buyer. If the amount buys no share, the transaction reverts.
- **Voting:** one vote per address per proposal, not changeable. Weight equals the shares owned. Choices: for, against, abstain.
- **Duration:** fixed, set in the constructor, the same for every proposal.
- **Quorum:** votes cast (for, against and abstain) must be at least 40% of total shares.
- **Approval:** votes for must be strictly more than 50% of for + against. A tie is rejected. If everyone abstains with quorum reached, the proposal is rejected.
- **Outcome:** computed by `status(id)` after the deadline. States: `Pending`, `Approved`, `Rejected`, `QuorumNotReached`.

#### Main functions

| Function | Who | What it does |
|---|---|---|
| `buyShares(amount)` | anyone, sales phase | buys shares with the token |
| `closeSales()` | owner | closes sales, opens governance |
| `createProposal(title, description)` | shareholders, after closing | creates a proposal |
| `vote(id, choice)` | shareholders, before the deadline | votes with all owned shares |
| `status(id)` | anyone | outcome of the proposal |
| `viewProposal(id)` | anyone | full record of the proposal |

The constructor takes the token address, the exchange rate and the voting period in seconds. The owner is the deployer. Each function is documented in the natspec of `src/GovernanceDAO.sol`.

### Usage

Requires [Foundry](https://book.getfoundry.sh/).

```shell
forge build
forge test -vv
```

Dependencies (OpenZeppelin, forge-std) are git submodules in `lib/`: clone with `--recurse-submodules`, or run `git submodule update --init --recursive` afterwards.

### License

MIT, see `LICENSE`.

---

## Italiano

DAO per la community scientifica e tecnologica di DnA: i membri votano le proposte di governance con uno smart contract Ethereum a democrazia diretta. Progetto Foundry / Solidity.

### Come funziona

Il contratto `GovernanceDAO` ha due fasi separate e irreversibili.

1. **Vendita.** Chiunque compra azioni pagando con un token ERC-20 (`buyShares`). Non si può ancora proporre né votare.
2. **Governance.** Dopo `closeSales()` (solo owner) non si comprano più azioni. Gli azionisti creano proposte e votano. Il totale delle azioni è fisso, quindi non servono snapshot.

Le decisioni sono solo un registro (testo, voti aggregati, esito): il contratto non esegue nulla on-chain.

#### Regole

- **Prezzo:** `exchangeRate` azioni per token, azioni intere con arrotondamento per difetto. Si incassa solo il costo delle azioni ottenute (arrotondato per eccesso), il resto resta all'utente. Se l'importo non compra nemmeno un'azione, la transazione fallisce.
- **Voto:** un voto per indirizzo per proposta, non modificabile. Peso pari alle azioni possedute. Scelte: favorevole, contrario, astenuto.
- **Durata:** fissa, stabilita nel costruttore, uguale per tutte le proposte.
- **Quorum:** i voti espressi (favorevoli, contrari e astenuti) devono essere almeno il 40% delle azioni totali.
- **Approvazione:** i favorevoli devono superare il 50% di favorevoli più contrari. Il pareggio è respinto. Se votano tutti astenuti con quorum raggiunto, la proposta è respinta.
- **Esito:** calcolato da `status(id)` dopo la scadenza. Stati: `Pending`, `Approved`, `Rejected`, `QuorumNotReached`.

#### Funzioni principali

| Funzione | Chi | Cosa fa |
|---|---|---|
| `buyShares(amount)` | chiunque, fase di vendita | compra azioni con il token |
| `closeSales()` | owner | chiude la vendita, apre la governance |
| `createProposal(title, description)` | azionisti, dopo la chiusura | crea una proposta |
| `vote(id, choice)` | azionisti, entro la scadenza | vota con tutte le azioni possedute |
| `status(id)` | chiunque | esito della proposta |
| `viewProposal(id)` | chiunque | registro completo della proposta |

Il costruttore riceve l'indirizzo del token, il tasso di cambio e la durata del voto in secondi. L'owner è chi fa il deploy. Il dettaglio di ogni funzione è nel natspec in `src/GovernanceDAO.sol`.

### Uso

Requisiti: [Foundry](https://book.getfoundry.sh/).

```shell
forge build
forge test -vv
```

Le dipendenze (OpenZeppelin, forge-std) sono submodule git in `lib/`: clona con `--recurse-submodules`, oppure esegui poi `git submodule update --init --recursive`.

### Licenza

MIT, vedi `LICENSE`.
