// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OpenInterest} from "../../src/OpenInterest.sol";

/// @dev Only the native Foundry cheatcodes used here; no downloaded test dependency is required.
interface OIVm {
    function prank(address sender) external;
    function expectRevert(bytes calldata reason) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
}

abstract contract OITestBase {
    OIVm internal constant vm = OIVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    // These are isolated test actors, not launch configuration or deployment recipients.
    address internal constant ALICE = address(uint160(uint256(keccak256("OI test Alice"))));
    address internal constant BOB = address(uint160(uint256(keccak256("OI test Bob"))));
    address internal constant CAROL = address(uint160(uint256(keccak256("OI test Carol"))));
    address internal constant DAVE = address(uint160(uint256(keccak256("OI test Dave"))));

    OpenInterest internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public virtual {
        token = new OpenInterest();
    }

    /// @dev Inclusive bounds retain in-range inputs and do not discard fuzz cases.
    function bound(uint256 value, uint256 lower, uint256 upper) internal pure returns (uint256) {
        require(lower <= upper, "invalid test bounds");
        if (value >= lower && value <= upper) return value;
        return lower + value % (upper - lower + 1);
    }

    function _expectTransfer(address from, address to, uint256 amount) internal {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(from, to, amount);
    }

    function _expectApproval(address owner, address spender, uint256 amount) internal {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(owner, spender, amount);
    }

    function _assertSupply() internal view {
        require(token.totalSupply() == SUPPLY, "fixed supply changed");
        require(token.balanceOf(address(0)) == 0, "zero address acquired tokens");
    }
}
