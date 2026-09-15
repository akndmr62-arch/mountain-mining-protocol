# TEST REPORT (REWARD + DEPLOYMENT HARDENING)

## Executed commands
- `forge fmt --check`
- `forge build`
- `forge test`

## Command results
- `forge fmt --check` → **failed** in this environment: `forge: command not found`
- `forge build` → **failed** in this environment: `forge: command not found`
- `forge test` → **failed** in this environment: `forge: command not found`

## Test suite changes made
- `test/MiningProtocol.t.sol` keeps reward/security invariant coverage for MiningPass + MiningEngine + MiningVault + MountainToken.
- Added exhausted-cap boundary checks (including zero-elapsed exhausted-cap release path).
- Replaced brittle storage-slot assumptions with `stdstore` setter for `totalEmitted`.
- Added `test/DeploymentFactory.t.sol` for deterministic deployment prediction/wiring assertions and duplicate-salt deployment revert.
- Added final-audit deployment checks for nonce-order address prediction, one-shot `ImmutableProtocolDeployer`, no post-deployment token mint path, and no admin/setter surfaces on factory/deployer.
- Added explicit full lifecycle single-token flow test covering custody -> pendingReward -> claimAndRelease -> payout -> state clear.

## CI changes
- Added GitHub Actions workflow: `.github/workflows/ci.yml`
- CI runs:
  - `forge fmt --check`
  - `forge build`
  - `forge test`
- Triggers:
  - `pull_request`
  - `push` to `main`

## Notes
- Runtime pass/fail counts cannot be produced until Foundry is available in the execution environment.
