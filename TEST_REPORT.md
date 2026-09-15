# TEST REPORT (MINING ENGINE + VAULT REWARD MODEL)

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
- Replaced `test/MiningProtocol.t.sol` with integrated `MiningPass + MiningEngine + MiningVault + MountainToken` coverage.
- Added deterministic reward checks for all 7 classes over 1 day, 30 days, 1 year, and 20 years.
- Added boundary coverage for zero time, one second, exactly 20 years, and >20-year clamp behavior.
- Added authorization checks for unauthorized/wrong-miner claim attempts and double-claim prevention.
- Added custody lifecycle checks (active custody invariant and post-claim ownership restoration).
- Added cap/invariant checks for global emission clamp and full-capacity 20-year aggregate emission bound.
- Added fuzz coverage for elapsed-time clamp and formula agreement under bounded elapsed values.

## Notes
- Runtime pass/fail counts cannot be produced until Foundry is available in the execution environment.
