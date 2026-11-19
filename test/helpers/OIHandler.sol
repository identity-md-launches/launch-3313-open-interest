// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OpenInterest} from "../../src/OpenInterest.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {OIVm} from "./OITestBase.sol";

/// @notice Drives the real token, using five holders and an independent ledger of authorized flows.
/// @dev No token storage is edited. The initial ledger comes from the specified issuance, not
/// from balanceOf. Unexpected returns/reverts are sticky failures, never ignored handler reverts.
contract OIHandler {
    OIVm private constant vm = OIVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 public constant ACTOR_COUNT = 5;
    OpenInterest public immutable token;
    address[5] public actors;

    uint256[5] public received;
    uint256[5] public sent;
    uint256[5][5] public expectedAllowance;
    uint256 public unexpectedOutcomes;
    uint256 public successfulCalls;
    uint256 public rejectedCalls;
    uint256 public positiveTransfers;

    constructor(OpenInterest token_, address[5] memory actors_) {
        token = token_;
        actors = actors_;
    }

    function expectedBalance(uint256 actor) public view returns (uint256) {
        return SUPPLY / ACTOR_COUNT + received[actor] - sent[actor];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        uint256 from = fromSeed % ACTOR_COUNT;
        uint256 to = toSeed % ACTOR_COUNT;
        _transfer(from, to, _amount(amountSeed, expectedBalance(from)));
    }

    function transferAll(uint256 fromSeed, uint256 toSeed) external {
        uint256 from = fromSeed % ACTOR_COUNT;
        _transfer(from, toSeed % ACTOR_COUNT, expectedBalance(from));
    }

    function selfTransfer(uint256 actorSeed, uint256 amountSeed) external {
        uint256 actor = actorSeed % ACTOR_COUNT;
        _transfer(actor, actor, _amount(amountSeed, expectedBalance(actor)));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        uint256 owner = ownerSeed % ACTOR_COUNT;
        uint256 spender = spenderSeed % ACTOR_COUNT;
        uint256 amount;
        uint256 mode = amountSeed % 5;
        if (mode == 0) amount = 0;
        else if (mode == 1) amount = type(uint256).max;
        else if (mode == 2) amount = type(uint256).max - 1;
        else if (mode == 3) amount = bound(amountSeed, 0, SUPPLY);
        else amount = amountSeed;
        _approve(owner, spender, amount);
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        _approve(ownerSeed % ACTOR_COUNT, spenderSeed % ACTOR_COUNT, 0);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        uint256 owner = ownerSeed % ACTOR_COUNT;
        uint256 spender = spenderSeed % ACTOR_COUNT;
        uint256 to = toSeed % ACTOR_COUNT;
        uint256 limit = expectedBalance(owner);
        uint256 allowance = expectedAllowance[owner][spender];
        if (allowance < limit) limit = allowance;
        uint256 amount = _amount(amountSeed, limit);
        if (_succeeds(actors[spender], abi.encodeCall(token.transferFrom, (actors[owner], actors[to], amount)))) {
            if (allowance != type(uint256).max) expectedAllowance[owner][spender] = allowance - amount;
            _recordTransfer(owner, to, amount);
        }
    }

    function transferTooMuch(uint256 fromSeed, uint256 toSeed, uint256 excessSeed) external {
        uint256 from = fromSeed % ACTOR_COUNT;
        uint256 balance = expectedBalance(from);
        uint256 amount = balance + bound(excessSeed, 1, type(uint256).max - balance);
        _rejects(
            actors[from],
            abi.encodeCall(token.transfer, (actors[toSeed % ACTOR_COUNT], amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, actors[from], balance, amount)
        );
    }

    function transferFromTooMuch(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        uint256 owner = ownerSeed % ACTOR_COUNT;
        uint256 spender = spenderSeed % ACTOR_COUNT;
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 amount;
        bytes memory reason;
        if (allowance == type(uint256).max) {
            amount = expectedBalance(owner) + 1;
            reason = abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, actors[owner], expectedBalance(owner), amount
            );
        } else {
            amount = allowance + 1;
            reason = abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, actors[spender], allowance, amount
            );
        }
        _rejects(
            actors[spender],
            abi.encodeCall(token.transferFrom, (actors[owner], actors[toSeed % ACTOR_COUNT], amount)),
            reason
        );
    }

    function invalidRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        uint256 owner = ownerSeed % ACTOR_COUNT;
        uint256 spender = spenderSeed % ACTOR_COUNT;
        uint256 limit = expectedBalance(owner);
        bytes memory reason = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        if (delegated) {
            uint256 allowance = expectedAllowance[owner][spender];
            if (allowance < limit) limit = allowance;
            uint256 amount = _amount(amountSeed, limit);
            _rejects(actors[spender], abi.encodeCall(token.transferFrom, (actors[owner], address(0), amount)), reason);
        } else {
            _rejects(actors[owner], abi.encodeCall(token.transfer, (address(0), _amount(amountSeed, limit))), reason);
        }
    }

    function invalidSpender(uint256 ownerSeed, uint256 amount) external {
        _rejects(
            actors[ownerSeed % ACTOR_COUNT],
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        uint256 from = fromSeed % ACTOR_COUNT;
        uint256 to = toSeed % ACTOR_COUNT;
        uint256 amount = _amount(amountSeed, expectedBalance(from));
        // Do not continue a dependent leg if the outward call failed unexpectedly.
        if (_transfer(from, to, amount)) _transfer(to, from, amount);
    }

    function _approve(uint256 owner, uint256 spender, uint256 amount) private {
        if (_succeeds(actors[owner], abi.encodeCall(token.approve, (actors[spender], amount)))) {
            expectedAllowance[owner][spender] = amount;
        }
    }

    function _transfer(uint256 from, uint256 to, uint256 amount) private returns (bool) {
        bool ok = _succeeds(actors[from], abi.encodeCall(token.transfer, (actors[to], amount)));
        if (ok) _recordTransfer(from, to, amount);
        return ok;
    }

    function _recordTransfer(uint256 from, uint256 to, uint256 amount) private {
        sent[from] += amount;
        received[to] += amount;
        if (amount > 0) ++positiveTransfers;
        // Check each leg as well as the final state: a round trip must not hide a wrong credit.
        if (
            token.balanceOf(actors[from]) != expectedBalance(from) || token.balanceOf(actors[to]) != expectedBalance(to)
        ) {
            ++unexpectedOutcomes;
        }
    }

    function _succeeds(address caller, bytes memory data) private returns (bool) {
        vm.prank(caller);
        (bool ok, bytes memory result) = address(token).call(data);
        if (!ok || keccak256(result) != keccak256(abi.encode(true))) {
            ++unexpectedOutcomes;
            return false;
        }
        ++successfulCalls;
        return true;
    }

    function _rejects(address caller, bytes memory data, bytes memory reason) private {
        vm.prank(caller);
        (bool ok, bytes memory result) = address(token).call(data);
        if (ok || keccak256(result) != keccak256(reason)) ++unexpectedOutcomes;
        else ++rejectedCalls;
    }

    /// @dev Bias towards zero, one wei, and the entire available amount as well as interior values.
    function _amount(uint256 seed, uint256 limit) private pure returns (uint256) {
        if (seed % 4 == 0) return 0;
        if (seed % 4 == 1) return limit == 0 ? 0 : 1;
        if (seed % 4 == 2) return limit;
        return bound(seed, 0, limit);
    }

    function bound(uint256 value, uint256 lower, uint256 upper) private pure returns (uint256) {
        if (value >= lower && value <= upper) return value;
        return lower + value % (upper - lower + 1);
    }
}
