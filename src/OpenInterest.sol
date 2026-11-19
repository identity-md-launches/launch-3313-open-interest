// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Fixed-supply OI token. The creating account receives the entire issuance.
contract OpenInterest is ERC20 {
    uint256 private constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Open Interest", "OI") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
