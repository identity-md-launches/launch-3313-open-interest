// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OpenInterest} from "../src/OpenInterest.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface Vm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
    function prank(address sender) external;
    function expectRevert(bytes calldata reason) external;
}

contract OpenInterestTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant SUPPLY = 10 ** 27;
    address private constant HOLDER = address(0xA11CE);
    address private constant SPENDER = address(0xB0B);

    OpenInterest private token;

    function setUp() public {
        token = new OpenInterest();
    }

    function testMetadataAndInitialSupply() public view {
        assert(keccak256(bytes(token.name())) == keccak256("Open Interest"));
        assert(keccak256(bytes(token.symbol())) == keccak256("OI"));
        assert(token.decimals() == 18);
        assert(token.totalSupply() == SUPPLY);
        assert(token.balanceOf(address(this)) == SUPPLY);
    }

    function testConstructorEmitsOneMintToCreatingContract() public {
        vm.recordLogs();
        OpenInterest created = new OpenInterest();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assert(logs.length == 1);
        assert(logs[0].emitter == address(created));
        assert(logs[0].topics.length == 3);
        assert(logs[0].topics[0] == IERC20.Transfer.selector);
        assert(logs[0].topics[1] == bytes32(0));
        assert(logs[0].topics[2] == bytes32(uint256(uint160(address(this)))));
        assert(abi.decode(logs[0].data, (uint256)) == SUPPLY);
    }

    function testDeployerCannotMintAgain() public {
        (bool success,) = address(token).call(abi.encodeWithSignature("mint(address,uint256)", HOLDER, 1));
        assert(!success);
        assert(token.totalSupply() == SUPPLY);
        assert(token.balanceOf(HOLDER) == 0);
    }

    function testFactoryDistributionAndClaimDeliverExactAmounts() public {
        address distributor = address(0xD157);
        address pool = address(0x9001);
        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = 8 * swarmShare;

        assert(token.transfer(distributor, swarmShare));
        assert(token.transfer(pool, poolShare));
        assert(token.transfer(HOLDER, SUPPLY - swarmShare - poolShare));
        assert(token.balanceOf(address(this)) == 0);
        assert(token.balanceOf(distributor) == swarmShare);
        assert(token.balanceOf(pool) == poolShare);
        assert(token.balanceOf(HOLDER) == SUPPLY - swarmShare - poolShare);

        vm.prank(distributor);
        assert(token.transfer(SPENDER, swarmShare));
        assert(token.balanceOf(distributor) == 0);
        assert(token.balanceOf(SPENDER) == swarmShare);
        assert(token.totalSupply() == SUPPLY);
    }

    function testFuzzDelegatedTransfersConserveSupply(uint96 rawFunding, uint96 rawSpending) public {
        uint256 funding = uint256(rawFunding) % (SUPPLY + 1);
        uint256 spending = uint256(rawSpending) % (funding + 1);
        assert(token.transfer(HOLDER, funding));
        vm.prank(HOLDER);
        assert(token.approve(SPENDER, funding));
        vm.prank(SPENDER);
        assert(token.transferFrom(HOLDER, SPENDER, spending));

        assert(token.allowance(HOLDER, SPENDER) == funding - spending);
        assert(token.balanceOf(address(this)) == SUPPLY - funding);
        assert(token.balanceOf(HOLDER) == funding - spending);
        assert(token.balanceOf(SPENDER) == spending);
        assert(token.totalSupply() == SUPPLY);
    }

    function testDeployerCannotSpendRevokedAllowance() public {
        assert(token.transfer(HOLDER, 100));
        vm.prank(HOLDER);
        assert(token.approve(address(this), 100));
        vm.prank(HOLDER);
        assert(token.approve(address(this), 0));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(HOLDER, SPENDER, 1);
        assert(token.balanceOf(HOLDER) == 100);
        assert(token.balanceOf(SPENDER) == 0);
    }

    function testInsufficientBalancePreservesAllowance() public {
        vm.prank(HOLDER);
        assert(token.approve(address(this), 10));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, HOLDER, 0, 10));
        token.transferFrom(HOLDER, SPENDER, 10);
        assert(token.allowance(HOLDER, address(this)) == 10);
        assert(token.balanceOf(SPENDER) == 0);
    }

    function testTransferToZeroRevertsWithoutBurning() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assert(token.balanceOf(address(this)) == SUPPLY);
        assert(token.totalSupply() == SUPPLY);
    }
}
