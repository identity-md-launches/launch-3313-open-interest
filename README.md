# Open Interest (OI)

Open Interest is a fixed-supply ERC-20. Its constructor credits the creating account with **1,000,000,000 OI** and emits a single `Transfer` from the zero address. OI uses 18 decimals, so `totalSupply()` returns `1000000000000000000000000000` base units.

## Deployment

| Parameter | Value |
| --- | --- |
| Launch chain | Ethereum mainnet (chain ID 1) |
| Contract | `src/OpenInterest.sol:OpenInterest` |
| Constructor arguments | `[]` |
| ETH sent at creation | 0 |
| Initial holder | The immediate deployer (`msg.sender` in the constructor) |

For the IMD launch, the factory creates the contract and receives the entire issuance. It allocates 100,000,000 OI to the swarm distributor, 800,000,000 OI to seed the imdUSD pool, and the remaining 100,000,000 OI to the requester's recipient at `0xd0116c7e933029a0abfa388757a3d7a7686ee681`. These transfers are the factory's responsibility after construction.

## After launch

The contract is ready at creation. Supply and transfer rules are permanent. The deployer has the same permissions as any other holder after distribution. Each holder controls its balance and is responsible for setting or revoking spender allowances. Transfers deliver the full requested amount. A finite allowance decreases by the amount spent, and a maximum-`uint256` allowance remains in effect until the holder changes it.

## Local verification

Use Foundry with Solidity 0.8.26 installed. The required sources from OpenZeppelin Contracts 5.4.0 and their MIT license are included in `lib/openzeppelin-contracts/` for offline builds.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x95b6313c2b55c897281a8b6ed7d00a5c0e98ec8a7d9878edbb26ed0086f9d6b5 forge test
forge fmt --check
```
