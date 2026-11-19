// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OIHandler} from "./helpers/OIHandler.sol";
import {OITestBase} from "./helpers/OITestBase.sol";

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
contract OpenInterestInvariantTest is OITestBase {
    OIHandler private handler;
    address[5] private actors;

    // Foundry's native invariant-target ABI, equivalent to StdInvariant's getters.
    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    function setUp() public override {
        super.setUp();
        actors = [address(this), ALICE, BOB, CAROL, DAVE];
        for (uint256 i = 1; i < actors.length; ++i) {
            require(token.transfer(actors[i], SUPPLY / actors.length), "initial distribution failed");
        }
        handler = new OIHandler(token, actors);
    }

    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function targetSelectors() public view returns (FuzzSelector[] memory targets) {
        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.transferAll.selector;
        selectors[2] = handler.selfTransfer.selector;
        selectors[3] = handler.approve.selector;
        selectors[4] = handler.revoke.selector;
        selectors[5] = handler.transferFrom.selector;
        selectors[6] = handler.transferTooMuch.selector;
        selectors[7] = handler.transferFromTooMuch.selector;
        selectors[8] = handler.invalidRecipient.selector;
        selectors[9] = handler.invalidSpender.selector;
        selectors[10] = handler.roundTrip.selector;
        targets = new FuzzSelector[](1);
        targets[0] = FuzzSelector(address(handler), selectors);
    }

    function invariantFixedSupplyAndConservation() public view {
        _assertSupply();
        uint256 balances;
        for (uint256 i; i < actors.length; ++i) {
            balances += token.balanceOf(actors[i]);
        }
        require(balances == SUPPLY, "tracked holders do not conserve issuance");
        require(token.balanceOf(address(handler)) == 0, "handler acquired tokens");
        require(token.balanceOf(address(token)) == 0, "token withheld a fee");
    }

    function invariantBalancesMatchAuthorizedFlows() public view {
        for (uint256 i; i < actors.length; ++i) {
            require(token.balanceOf(actors[i]) == handler.expectedBalance(i), "balance differs from authorized flows");
        }
    }

    function invariantAllowancesMatchAuthorizationHistory() public view {
        for (uint256 i; i < actors.length; ++i) {
            require(token.allowance(actors[i], address(0)) == 0, "zero spender gained authorization");
            require(token.allowance(address(0), actors[i]) == 0, "zero owner gained authorization");
            for (uint256 j; j < actors.length; ++j) {
                require(
                    token.allowance(actors[i], actors[j]) == handler.expectedAllowance(i, j),
                    "allowance differs from authorization history"
                );
            }
        }
    }

    function invariantValidCallsSucceedAndInvalidCallsRevertExactly() public view {
        require(handler.unexpectedOutcomes() == 0, "unexpected return, revert, or transfer result");
    }

    function invariantMetadataRemainsFixed() public view {
        require(keccak256(bytes(token.name())) == keccak256("Open Interest"), "name changed");
        require(keccak256(bytes(token.symbol())) == keccak256("OI"), "symbol changed");
        require(token.decimals() == 18, "decimals changed");
    }

    /// @dev A deterministic non-vacuity witness exercises all handler entry points and the model.
    function testHandlerExercisesSuccessFailureRevocationAndInfiniteApproval() public {
        handler.transfer(0, 1, 1);
        handler.transferAll(1, 2);
        handler.selfTransfer(2, 2);
        handler.approve(2, 3, 3); // finite allowance of three wei
        handler.transferFrom(2, 3, 4, 1);
        handler.approve(2, 3, 1); // maximum approval
        handler.transferFrom(2, 3, 4, 1);
        require(handler.expectedAllowance(2, 3) == type(uint256).max, "infinite path not reached");
        handler.transferFromTooMuch(2, 3, 4); // sufficient allowance, insufficient balance
        handler.revoke(2, 3);
        handler.transferFromTooMuch(2, 3, 4); // insufficient allowance
        handler.transferTooMuch(0, 1, 1);
        handler.invalidRecipient(0, 1, 1, false);
        handler.invalidRecipient(0, 1, 0, true);
        handler.invalidSpender(0, 1);
        handler.roundTrip(2, 4, 1);

        require(handler.successfulCalls() > 0 && handler.positiveTransfers() > 0, "no successful movement");
        require(handler.rejectedCalls() == 6, "failure paths not reached");
        invariantFixedSupplyAndConservation();
        invariantBalancesMatchAuthorizedFlows();
        invariantAllowancesMatchAuthorizationHistory();
        invariantValidCallsSucceedAndInvalidCallsRevertExactly();
        invariantMetadataRemainsFixed();
    }
}
