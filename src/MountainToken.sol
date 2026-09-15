// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title MountainToken (MMP)
/// @notice Skeleton only. Production logic intentionally deferred.
/// @dev No MiningMinter and no mint function of any kind exists after construction. The full
/// fixed supply is minted exactly once, in the constructor, to `initialHolder`. A deployment
/// script then performs one ordinary ERC20 `transfer` of that full balance to MiningVault; the
/// token contract itself never references MiningVault and never mints again.
contract MountainToken {
    // TODO: Implement non-upgradeable ERC20 with 18 decimals on Base.
    // TODO: Constructor mints exactly 1,000,000,000 MMP once to `initialHolder` and to no other
    //       address; there is no separate/public/owner/admin mint function anywhere in the
    //       contract, so there is no post-deployment mint path, hidden mint path, or supply
    //       expansion mechanism of any kind.
}
