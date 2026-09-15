// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";

contract Deploy is Script {
    function run() external {
        // Deployment sequencing (draft, see DEPLOYMENT.md):
        // 1. Precompute MiningVault's CREATE2 address.
        // 2. Deploy MiningPass with the precomputed MiningVault address wired in.
        // 3. Deploy MiningVault via CREATE2 with MiningPass's real address; revert on address
        //    mismatch against the precomputed value.
        // 4. Deploy MountainToken, minting the full fixed supply once to `initialHolder`.
        // 5. Transfer MountainToken's full balance from `initialHolder` to MiningVault via an
        //    ordinary ERC20 transfer. No mint call is ever made after step 4.
    }
}
