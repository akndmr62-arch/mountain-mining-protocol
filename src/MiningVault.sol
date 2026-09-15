// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title MiningVault
/// @notice Skeleton only. Production logic intentionally deferred.
/// @dev Sole authority for the CLAIM step of the mining lifecycle. There is no MiningEngine and
/// no MiningMinter: MiningVault reads MiningPass state directly, computes the reward itself, and
/// pays out from its own pre-funded MMP balance (never by minting). No other contract may
/// calculate reward, mining power, or recipient, or override MiningVault/MiningPass.
contract MiningVault {
    // TODO: Hold the full pre-funded MMP reward reserve (transferred in once at deployment,
    //       never minted here or anywhere post-deployment) and compute rewards independently
    //       from MiningPass state (power, startedAt, active) with no engine/caller-provided inputs.
    // TODO: Enforce floor rounding and totalEmitted + reward <= 1,000,000,000 MMP at all times;
    //       reject the claim if the cap would be exceeded rather than partially paying out.
    // TODO: Reject any caller-provided reward/power/startTime/recipient authority; all inputs are
    //       read from MiningPass via getMiningPosition/miningOwner and are never passed by the caller.
    // TODO: Enforce active-custody verification (MiningPass.isMining) and the 20-year per-period
    //       elapsed-time clamp (630_720_000 seconds) before computing reward.
    // TODO: Implement claimAndRelease(tokenId): validate mining state -> compute reward ->
    //       update emission accounting -> transfer() MMP from own balance to the recorded miner ->
    //       call MiningPass.releaseFromMining(tokenId) to release the NFT to that same recorded
    //       miner. Any failure in either step reverts the whole transaction; no partial state.
    // TODO: Resolve the MiningVault<->MiningPass circular constructor dependency with a one-time,
    //       non-privileged CREATE2 deployer: precompute this Vault's address and pass it into
    //       MiningPass's constructor, deploy MiningVault via CREATE2 with MiningPass's real
    //       address as an immutable constructor argument, and revert the whole deployment
    //       transaction if the deployed address does not match the precomputed one. No mutable
    //       setter, owner, or admin role is introduced to solve this.
}
