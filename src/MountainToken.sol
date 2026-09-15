// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @title MountainToken (MMP)
/// @notice Fixed-supply ERC-20 token with no post-deployment mint path.
contract MountainToken is ERC20 {
    error InvalidAddress();

    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    constructor(address initialHolder) ERC20("Mountain Mining Protocol", "MMP") {
        if (initialHolder == address(0)) {
            revert InvalidAddress();
        }
        _mint(initialHolder, MAX_SUPPLY);
    }
}
