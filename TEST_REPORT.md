# TEST REPORT (REWARD + DEPLOYMENT HARDENING)

## Executed commands
- `forge fmt`
- `forge build`
- `forge test`
- `forge test -vvv`

## Command results
- `forge fmt` → **failed** in this environment: `forge: command not found`
- `forge build` → **failed** in this environment: `forge: command not found`
- `forge test` → **failed** in this environment: `forge: command not found`
- `forge test -vvv` → **failed** in this environment: `forge: command not found`

## Test suite changes made
- `test/MiningProtocol.t.sol` keeps reward/security invariant coverage for MiningPass + MiningEngine + MiningVault + MountainToken.
- Added exhausted-cap boundary checks (including zero-elapsed exhausted-cap release path).
- Replaced brittle storage-slot assumptions with `stdstore` setter for `totalEmitted`.
- Added `test/DeploymentFactory.t.sol` for deterministic deployment prediction/wiring assertions and duplicate-salt deployment revert.

## CI changes
- Added GitHub Actions workflow: `.github/workflows/foundry-ci.yml`
- CI runs:
  - `forge fmt --check`
  - `forge build`
  - `forge test`
- Triggers:
  - `pull_request`
  - `push` to `main`

## Notes
- Runtime pass/fail counts cannot be produced until Foundry is available in the execution environment.
