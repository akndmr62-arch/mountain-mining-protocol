# DEPLOYMENT

## Objective
Deploy protocol contracts with immutable constructor wiring and no post-deployment dependency rewiring.

## Dependency graph
- `MiningPass` constructor requires:
  - `miningEngine`
  - `miningMinter`
- `MiningVault` constructor requires:
  - `miningPass`
  - `miningEngine`
  - `mountainToken`
- `MountainToken` constructor requires:
  - `initialHolder` (`MiningVault`)
- `MiningEngine` constructor requires:
  - `miningPass`
  - `miningVault`
- `MiningMinter` currently has no constructor parameters.

## Why naive sequential deployment fails
The graph has a constructor cycle:
- `MiningPass -> MiningEngine -> MiningVault -> MiningPass`
- `MiningVault -> MountainToken -> MiningVault`

Direct deployment with unknown runtime addresses cannot satisfy all immutable constructor arguments without precomputed addresses.

## Chosen immutable solution
Use a two-stage deterministic deployment mechanism:
1. `ProtocolDeploymentFactory` deploys `ImmutableProtocolDeployer` with `CREATE2` using a caller-supplied salt.
2. `ImmutableProtocolDeployer` deploys protocol contracts with `CREATE` in a fixed nonce order.

This works because contract addresses from `CREATE` depend on `(deployerAddress, nonce)` and do **not** depend on constructor parameters.

## Deterministic address derivation
Given:
- `factory = address(ProtocolDeploymentFactory)`
- `salt = bytes32 deployment salt`

Addresses are deterministic as:
1. `deployer = CREATE2(factory, salt, keccak256(ImmutableProtocolDeployer.creationCode))`
2. `miningPass = CREATE(deployer, nonce=1)`
3. `miningMinter = CREATE(deployer, nonce=2)`
4. `miningVault = CREATE(deployer, nonce=3)`
5. `mountainToken = CREATE(deployer, nonce=4)`
6. `miningEngine = CREATE(deployer, nonce=5)`

`ProtocolDeploymentFactory.predictProtocol(salt)` returns these addresses before deployment.

## Deployment order and constructor parameters
`ImmutableProtocolDeployer.deploy(...)` executes in this exact order:
1. `MiningPass(predictedMiningEngine, predictedMiningMinter)`
2. `MiningMinter()`
3. `MiningVault(miningPass, predictedMiningEngine, predictedMountainToken)`
4. `MountainToken(miningVault)`
5. `MiningEngine(miningPass, miningVault)`

The deployer asserts:
- deployed addresses equal predicted addresses
- constructor wiring equals expected immutable references

## MountainToken 1B supply path
- `MountainToken` mints exactly `1_000_000_000 ether` once in constructor.
- `initialHolder` is `MiningVault`.
- No post-deployment mint path exists.

## Script usage
Use `script/Deploy.s.sol`:
- optional `MMP_FACTORY_ADDRESS` to reuse an existing factory
- optional `MMP_PROTOCOL_SALT` for deployment salt (default `bytes32("MMP_PROTOCOL_V1")`)

The script:
- predicts addresses
- deploys protocol through `ProtocolDeploymentFactory.deployProtocol(salt)`
- asserts deployed == predicted
- logs resulting addresses

## Security constraints preserved
- No mutable dependency setters
- No upgradeability
- No owner/admin rewiring controls
- No reward parameter mutation at deployment or runtime
