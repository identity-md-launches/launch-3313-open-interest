// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OpenInterest} from "../src/OpenInterest.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {OITestBase} from "./helpers/OITestBase.sol";

contract OICreator {
    function create() external returns (OpenInterest) {
        return new OpenInterest();
    }
}

/// @notice Adds adversarial and boundary coverage without replacing the original launch tests.
/// forge-config: default.fuzz.runs = 1000
contract OpenInterestBehaviorTest is OITestBase {
    function testConstructorMintsToImmediateCreatorRatherThanItsCaller() public {
        OICreator creator = new OICreator();
        vm.prank(ALICE);
        OpenInterest created = creator.create();
        require(created.balanceOf(address(creator)) == SUPPLY, "creator did not receive issuance");
        require(created.balanceOf(ALICE) == 0, "creator's caller received issuance");
        require(created.balanceOf(address(this)) == 0, "test deployer received issuance");
        require(created.totalSupply() == SUPPLY, "incorrect issuance");
    }

    function testZeroTransferFromEmptyAccountSucceedsAndEmits() public {
        _expectTransfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        require(token.transfer(BOB, 0), "zero transfer returned false");
        require(token.balanceOf(ALICE) == 0 && token.balanceOf(BOB) == 0, "zero transfer moved tokens");
        require(token.balanceOf(address(this)) == SUPPLY, "unrelated balance changed");
        _assertSupply();
    }

    function testOneWeiTransferIsNotRoundedOrTaxed() public {
        _expectTransfer(address(this), ALICE, 1);
        require(token.transfer(ALICE, 1), "one wei transfer failed");
        require(token.balanceOf(ALICE) == 1, "one wei arrived short");
        require(token.balanceOf(address(this)) == SUPPLY - 1, "incorrect one wei debit");
        _assertSupply();
    }

    function testEntireSupplyCanMoveAndReturn() public {
        _expectTransfer(address(this), ALICE, SUPPLY);
        require(token.transfer(ALICE, SUPPLY), "full transfer failed");
        require(token.balanceOf(address(this)) == 0, "full transfer left dust");
        require(token.balanceOf(ALICE) == SUPPLY, "full transfer arrived short");
        _expectTransfer(ALICE, address(this), SUPPLY);
        vm.prank(ALICE);
        require(token.transfer(address(this), SUPPLY), "return transfer failed");
        require(token.balanceOf(address(this)) == SUPPLY && token.balanceOf(ALICE) == 0, "round trip lost value");
        _assertSupply();
    }

    function testSelfTransferOfEntireSupplyAndZeroLeavesBalanceUnchanged() public {
        _expectTransfer(address(this), address(this), SUPPLY);
        require(token.transfer(address(this), SUPPLY), "full self transfer failed");
        require(token.balanceOf(address(this)) == SUPPLY, "self transfer changed balance");
        _expectTransfer(address(this), address(this), 0);
        require(token.transfer(address(this), 0), "zero self transfer failed");
        require(token.balanceOf(address(this)) == SUPPLY, "zero self transfer changed balance");
        _assertSupply();
    }

    function testSelfTransferStillRequiresSufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        require(token.balanceOf(address(this)) == SUPPLY, "failed self transfer changed balance");
        _assertSupply();
    }

    function testTransferMoreThanBalanceAndUintMaxRevertAtomically() public {
        uint256[2] memory amounts = [SUPPLY + 1, type(uint256).max];
        for (uint256 i; i < amounts.length; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amounts[i]
                )
            );
            token.transfer(ALICE, amounts[i]);
            require(
                token.balanceOf(address(this)) == SUPPLY && token.balanceOf(ALICE) == 0, "failed transfer moved tokens"
            );
            _assertSupply();
        }
    }

    function testZeroTransferToZeroAddressAlsoReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        require(token.balanceOf(address(this)) == SUPPLY, "invalid receiver changed balance");
        _assertSupply();
    }

    function testZeroSenderCannotTransferEvenZero() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(ALICE, 0);
        require(token.balanceOf(ALICE) == 0, "zero sender minted tokens");
        _assertSupply();
    }

    function testTokenContractCanReceiveAnExactTransfer() public {
        require(token.transfer(address(token), 1), "contract recipient transfer failed");
        require(token.balanceOf(address(token)) == 1, "contract recipient not credited");
        require(token.balanceOf(address(this)) == SUPPLY - 1, "incorrect contract transfer debit");
        _assertSupply();
    }

    function testApproveOverwritesIsIdempotentAndCanRevoke() public {
        uint256[5] memory amounts = [uint256(7), 7, 3, type(uint256).max, 0];
        for (uint256 i; i < amounts.length; ++i) {
            _expectApproval(ALICE, BOB, amounts[i]);
            vm.prank(ALICE);
            require(token.approve(BOB, amounts[i]), "approval returned false");
            require(token.allowance(ALICE, BOB) == amounts[i], "approval was not replaced");
            require(token.allowance(BOB, ALICE) == 0, "approval leaked to reverse pair");
            require(token.balanceOf(ALICE) == 0, "approval changed balance");
            require(token.balanceOf(address(this)) == SUPPLY, "approval changed holder balance");
            _assertSupply();
        }
    }

    function testApprovalToZeroSpenderRevertsForZeroAndMaximum() public {
        uint256[2] memory amounts = [uint256(0), type(uint256).max];
        for (uint256 i; i < amounts.length; ++i) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            token.approve(address(0), amounts[i]);
            require(token.allowance(address(this), address(0)) == 0, "invalid spender gained allowance");
            require(token.balanceOf(address(this)) == SUPPLY, "invalid approval moved tokens");
            _assertSupply();
        }
    }

    function testZeroApproverCannotCreateAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(BOB, 1);
        require(token.allowance(address(0), BOB) == 0, "zero approver granted allowance");
        _assertSupply();
    }

    function testAllowanceIsScopedToBothOwnerAndSpender() public {
        require(token.transfer(ALICE, 10), "fund Alice");
        require(token.transfer(CAROL, 10), "fund Carol");
        vm.prank(ALICE);
        require(token.approve(BOB, 10), "approve Bob");

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, DAVE, 0, 1));
        vm.prank(DAVE);
        token.transferFrom(ALICE, DAVE, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(CAROL, BOB, 1);

        require(token.allowance(ALICE, BOB) == 10, "unrelated failure consumed approval");
        require(token.balanceOf(ALICE) == 10 && token.balanceOf(CAROL) == 10, "unauthorized debit");
        require(token.balanceOf(BOB) == 0 && token.balanceOf(DAVE) == 0, "unauthorized credit");
        _assertSupply();
    }

    function testFiniteAllowanceCanBeConsumedExactlyOnce() public {
        require(token.approve(BOB, 10), "approve");
        _expectTransfer(address(this), CAROL, 10);
        vm.prank(BOB);
        require(token.transferFrom(address(this), CAROL, 10), "delegated transfer failed");
        require(token.allowance(address(this), BOB) == 0, "allowance not exhausted");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), CAROL, 1);
        require(token.balanceOf(CAROL) == 10, "replayed authorization");
        require(token.balanceOf(address(this)) == SUPPLY - 10, "incorrect owner debit");
        _assertSupply();
    }

    function testMaximumAllowanceSurvivesRepeatedSpendingAndCanBeRevoked() public {
        require(token.approve(BOB, type(uint256).max), "approve infinite");
        vm.prank(BOB);
        require(token.transferFrom(address(this), ALICE, 1), "spend one");
        require(token.allowance(address(this), BOB) == type(uint256).max, "infinite allowance decremented");
        vm.prank(BOB);
        require(token.transferFrom(address(this), ALICE, SUPPLY - 1), "spend remainder");
        require(token.allowance(address(this), BOB) == type(uint256).max, "infinite allowance exhausted");
        vm.prank(ALICE);
        require(token.transfer(address(this), SUPPLY), "return funds");
        require(token.approve(BOB, 0), "revoke infinite");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), ALICE, 1);
        require(token.balanceOf(address(this)) == SUPPLY && token.balanceOf(ALICE) == 0, "revoked allowance spent");
        _assertSupply();
    }

    function testLargestFiniteAllowanceIsDecremented() public {
        require(token.approve(BOB, type(uint256).max - 1), "approve largest finite");
        vm.prank(BOB);
        require(token.transferFrom(address(this), CAROL, 1), "finite transfer failed");
        require(token.allowance(address(this), BOB) == type(uint256).max - 2, "finite treated as infinite");
        require(
            token.balanceOf(CAROL) == 1 && token.balanceOf(address(this)) == SUPPLY - 1, "incorrect finite transfer"
        );
        _assertSupply();
    }

    function testZeroDelegatedTransferNeedsNoApprovalAndEmits() public {
        _expectTransfer(ALICE, CAROL, 0);
        vm.prank(BOB);
        require(token.transferFrom(ALICE, CAROL, 0), "zero delegated transfer failed");
        require(token.allowance(ALICE, BOB) == 0, "zero transfer created allowance");
        require(token.balanceOf(ALICE) == 0 && token.balanceOf(CAROL) == 0, "zero delegated transfer moved tokens");
        _assertSupply();
    }

    function testDelegatedSelfTransferConsumesAllowanceButPreservesBalance() public {
        require(token.approve(BOB, SUPPLY), "approve self transfer");
        _expectTransfer(address(this), address(this), SUPPLY);
        vm.prank(BOB);
        require(token.transferFrom(address(this), address(this), SUPPLY), "delegated self transfer failed");
        require(token.balanceOf(address(this)) == SUPPLY, "delegated self transfer changed balance");
        require(token.allowance(address(this), BOB) == 0, "delegated self transfer did not consume allowance");
        _assertSupply();
    }

    function testTransferFromByOwnerStillRequiresAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        require(token.approve(address(this), 1), "self approval");
        require(token.transferFrom(address(this), ALICE, 1), "self approved transfer");
        require(token.allowance(address(this), address(this)) == 0, "self allowance not spent");
        require(token.balanceOf(ALICE) == 1 && token.balanceOf(address(this)) == SUPPLY - 1, "self spender accounting");
        _assertSupply();
    }

    function testInvalidDelegatedRecipientRollsBackAllowance() public {
        require(token.approve(BOB, 10), "approve");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(BOB);
        token.transferFrom(address(this), address(0), 10);
        require(token.allowance(address(this), BOB) == 10, "failed transfer consumed allowance");
        require(token.balanceOf(address(this)) == SUPPLY, "failed transfer burned tokens");
        _assertSupply();
    }

    function testDelegatedTransferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(BOB);
        token.transferFrom(ALICE, address(0), 0);
        require(token.allowance(ALICE, BOB) == 0, "invalid zero transfer changed approval");
        _assertSupply();
    }

    function testDelegatedTransferFromZeroCannotMintEvenForZeroAmount() public {
        uint256[3] memory amounts = [uint256(0), 1, type(uint256).max];
        for (uint256 i; i < amounts.length; ++i) {
            vm.prank(BOB);
            (bool ok,) = address(token).call(abi.encodeCall(token.transferFrom, (address(0), ALICE, amounts[i])));
            // Rejection is required; allowance validation may reject before sender validation.
            require(!ok, "transferFrom accepted the zero owner");
            require(token.balanceOf(ALICE) == 0, "zero owner minted tokens");
            require(token.allowance(address(0), BOB) == 0, "zero owner gained allowance");
            require(token.balanceOf(address(this)) == SUPPLY, "invalid owner changed holder balance");
            _assertSupply();
        }
    }

    function testInfiniteAllowanceDoesNotPermitSpendingBeyondBalance() public {
        require(token.approve(BOB, type(uint256).max), "approve");
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(BOB);
        token.transferFrom(address(this), ALICE, type(uint256).max);
        require(token.allowance(address(this), BOB) == type(uint256).max, "failure consumed infinite allowance");
        require(token.balanceOf(address(this)) == SUPPLY && token.balanceOf(ALICE) == 0, "overspend moved tokens");
        _assertSupply();
    }

    function testNoPostDeploymentMintBurnOrAdminEntryPoints() public {
        require(token.transfer(ALICE, 10), "fund holder");
        bytes[9] memory calls = [
            abi.encodeWithSignature("mint(address,uint256)", BOB, 1),
            abi.encodeWithSignature("mint(uint256)", 1),
            abi.encodeWithSignature("burn(uint256)", 1),
            abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1),
            abi.encodeWithSignature("initialize(address)", BOB),
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("blacklist(address)", ALICE),
            abi.encodeWithSignature("transferOwnership(address)", BOB),
            abi.encodeWithSignature("upgradeTo(address)", BOB)
        ];
        address[2] memory callers = [address(this), BOB];
        for (uint256 c; c < callers.length; ++c) {
            for (uint256 i; i < calls.length; ++i) {
                vm.prank(callers[c]);
                (bool ok,) = address(token).call(calls[i]);
                require(!ok, "unexpected mint, burn or privileged entry point");
                require(token.balanceOf(ALICE) == 10 && token.balanceOf(BOB) == 0, "admin probe moved holder tokens");
                require(token.balanceOf(address(this)) == SUPPLY - 10, "admin probe changed deployer balance");
                _assertSupply();
            }
        }
        vm.prank(ALICE);
        require(token.transfer(CAROL, 10), "holder frozen after probes");
        require(token.balanceOf(CAROL) == 10 && token.balanceOf(ALICE) == 0, "holder transfer short");
    }

    function testFuzzTransferAndReverseRestoreBalances(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        require(token.transfer(ALICE, amount), "forward transfer failed");
        require(token.balanceOf(ALICE) == amount, "forward credit incorrect");
        require(token.balanceOf(address(this)) == SUPPLY - amount, "forward debit incorrect");
        vm.prank(ALICE);
        require(token.transfer(address(this), amount), "reverse transfer failed");
        require(token.balanceOf(address(this)) == SUPPLY && token.balanceOf(ALICE) == 0, "round trip changed value");
        _assertSupply();
    }

    function testFuzzTransferToAnyNonzeroRecipient(address rawRecipient, uint256 rawAmount) public {
        address recipient = address(uint160(bound(uint160(rawRecipient), 1, type(uint160).max)));
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        _expectTransfer(address(this), recipient, amount);
        require(token.transfer(recipient, amount), "arbitrary recipient rejected");
        if (recipient == address(this)) {
            require(token.balanceOf(address(this)) == SUPPLY, "self recipient changed balance");
        } else {
            require(token.balanceOf(recipient) == amount, "arbitrary recipient credit incorrect");
            require(token.balanceOf(address(this)) == SUPPLY - amount, "arbitrary recipient debit incorrect");
        }
        _assertSupply();
    }

    function testFuzzSplitTransferEqualsCombinedTransfer(uint256 rawFirst, uint256 rawSecond) public {
        uint256 first = bound(rawFirst, 0, SUPPLY);
        uint256 second = bound(rawSecond, 0, SUPPLY - first);
        require(token.transfer(ALICE, first), "first leg failed");
        require(token.transfer(ALICE, second), "second leg failed");
        require(token.balanceOf(ALICE) == first + second, "split transfer loses precision");
        require(token.balanceOf(address(this)) == SUPPLY - (first + second), "split debit incorrect");
        _assertSupply();
    }

    function testFuzzDelegatedTransferMatchesDirectTransfer(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        OpenInterest direct = new OpenInterest();
        require(direct.transfer(ALICE, amount), "direct transfer");
        require(token.approve(BOB, amount), "approve delegation");
        vm.prank(BOB);
        require(token.transferFrom(address(this), ALICE, amount), "delegated transfer");
        require(token.balanceOf(ALICE) == direct.balanceOf(ALICE), "delegated credit differs");
        require(token.balanceOf(address(this)) == direct.balanceOf(address(this)), "delegated debit differs");
        require(token.balanceOf(BOB) == 0, "spender took funds");
        require(token.allowance(address(this), BOB) == 0, "exact allowance not spent");
        _assertSupply();
    }

    function testFuzzApprovalReplacementDoesNotChangeOtherAllowances(uint256 first, uint256 replacement) public {
        require(token.approve(BOB, first), "first approval");
        require(token.approve(CAROL, first), "independent approval");
        require(token.approve(BOB, replacement), "replacement approval");
        require(token.allowance(address(this), BOB) == replacement, "replacement not exact");
        require(token.allowance(address(this), CAROL) == first, "unrelated allowance changed");
        require(token.balanceOf(address(this)) == SUPPLY, "approval changed balance");
        _assertSupply();
    }

    function testFuzzInsufficientDirectBalanceReverts(uint256 rawBalance, uint256 rawExcess) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 excess = bound(rawExcess, 1, type(uint256).max - balance);
        require(token.transfer(ALICE, balance), "fund holder");
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, balance + excess)
        );
        vm.prank(ALICE);
        token.transfer(BOB, balance + excess);
        require(token.balanceOf(ALICE) == balance && token.balanceOf(BOB) == 0, "failed transfer mutated balances");
        require(token.balanceOf(address(this)) == SUPPLY - balance, "failed transfer changed unrelated holder");
        _assertSupply();
    }

    function testFuzzInsufficientAllowanceRevertsWithoutMovingFunds(uint256 rawAllowance, uint256 rawExcess) public {
        uint256 allowance = bound(rawAllowance, 0, SUPPLY - 1);
        uint256 amount = allowance + bound(rawExcess, 1, SUPPLY - allowance);
        require(token.approve(BOB, allowance), "approve");
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, allowance, amount)
        );
        vm.prank(BOB);
        token.transferFrom(address(this), CAROL, amount);
        require(token.allowance(address(this), BOB) == allowance, "failed spend changed allowance");
        require(token.balanceOf(address(this)) == SUPPLY && token.balanceOf(CAROL) == 0, "failed spend moved tokens");
        _assertSupply();
    }

    function testFuzzInsufficientDelegatedBalanceRollsBackFiniteAllowance(uint256 rawBalance, uint256 rawExcess)
        public
    {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 amount = balance + bound(rawExcess, 1, SUPPLY);
        require(token.transfer(ALICE, balance), "fund holder");
        vm.prank(ALICE);
        require(token.approve(BOB, amount), "approve unfunded amount");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, amount);
        require(token.allowance(ALICE, BOB) == amount, "balance failure consumed allowance");
        require(token.balanceOf(ALICE) == balance && token.balanceOf(CAROL) == 0, "balance failure moved tokens");
        _assertSupply();
    }
}
