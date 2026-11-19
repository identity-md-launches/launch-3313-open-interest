The original `OpenInterest.t.sol` is retained. `OpenInterestBehavior.t.sol` adds boundary,
failure, event, and algebraic property tests for the deployed `OpenInterest` contract.
Its fuzz properties run 1,000 cases each. No production contracts or configuration are changed,
and no additional dependencies, network access, forks, or private keys are needed.

The invariant suite runs 256 sequences of 128 calls through `helpers/OIHandler.sol`.
Five holders start with equal portions of the constructor's issuance; the deployer is one
of the holders. All recipients belong to this closed set, except rejected zero-address
recipients. Self-transfers and coincident owner/spender/recipient roles are allowed.
The suite exposes Foundry's native `targetContracts` and `targetSelectors` getters to target
only the eleven handler actions.

The property choices follow the five supplied discovery perspectives:

| Perspective | Property and basis |
| --- | --- |
| Conservation | The requested fixed supply stays at `10**27`; the sum of all tracked balances equals that issuance. |
| State transitions | `approve` replaces only the selected authorization; finite spending consumes it, maximum approval persists, and revocation prevents later spending. These are the inherited ERC-20 semantics. |
| Round trips and rounding | Transfers and their reversals restore exact balances, split transfers conserve every wei, and direct and delegated transfers deliver the same amount. This token has no conversions or transfer fees. |
| Unauthorized value extraction | Insufficient balances/allowances and invalid addresses must revert without changing the ledger; valid bounded transfers must succeed. Unit tests also probe mint, burn, and privileged entry points from deployer and stranger. |
| Token-specific properties | Metadata is fixed, zero transfers emit events, self-transfers preserve balances, and the zero address never holds tokens. |

The handler's ledger starts from the requested supply and records authorized incoming and
outgoing amounts independently of `balanceOf`. Allowances are tracked separately for all
25 owner/spender pairs. Bounds use this expected ledger, not balances read back from the
implementation. Each invariant runs after every handler call; round-trip legs also check
their intermediate balances. Unexpected return data, unexpected success, and unexpected
revert reasons increment a persistent failure counter, so Foundry's default tolerance of
handler reverts cannot silently bless these outcomes. A deterministic handler test exercises
every action, including positive delegated spending, revocation, and infinite allowances.

Wallet-gas applicability was checked in `src/OpenInterest.sol` and its inherited ERC-20 and
Context code. None checks `gasleft()`, forwards fixed gas, or catches an external call failure,
so the supplied WalletGas helper is not applicable. Low-level calls in the test handler only
observe the token's success and failure paths; they are not production entry points.

Run the offline checks with artifacts kept in the disposable scratch directory:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0x95b6313c2b55c897281a8b6ed7d00a5c0e98ec8a7d9878edbb26ed0086f9d6b5 forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```

Coverage includes the inherited library when requested with `forge coverage --include-libs`.
Internal burn functions and unused Context helpers are not exposed by this token; the tests
exercise the actual contract rather than a subclass that adds mint or burn access.
