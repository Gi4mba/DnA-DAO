// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GovernanceDAO} from "../src/GovernanceDAO.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract GovernanceDAOTest is Test {
    MockERC20 token;
    GovernanceDAO dao;
    address alice;
    address bob;

    uint256 constant RATE = 10;
    uint256 constant PERIOD = 7 days;

    event SalesClosed();
    event ProposalCreated(
        uint256 indexed id, address indexed proposer, uint64 endTime, string title, string description
    );

    /* SetUp() starts from a fresh new contract */
    function setUp() public {
        token = new MockERC20(18);
        dao = new GovernanceDAO(address(token), RATE, PERIOD);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
    }

    function mintAndBuy(address caller) internal {
        token.mint(caller, 1e18); /* MockERC20 can mint tokens */
        vm.prank(caller); /* NEXT call has msg.sender = alice */
        token.approve(address(dao), 1e18);
        vm.prank(caller);
        dao.buyShares(1e18);
    }

    /* Test checks if values are equal to the passed ones  */
    function test_Constructor_StoresConfig() public view {
        assertEq(dao.owner(), address(this));
        assertEq(address(dao.token()), address(token));
        assertEq(dao.exchangeRate(), RATE);
        assertEq(dao.votingPeriod(), PERIOD);
        assertEq(dao.tokenUnit(), 1e18);
        assertTrue(dao.salesOpen());
        assertEq(dao.totalShares(), 0);
        assertEq(dao.proposalCount(), 0);
    }

    /* Test on 6 decimals token */
    function test_Constructor_TokenUnitWith6Decimals() public {
        MockERC20 usdc = new MockERC20(6);
        GovernanceDAO dao6 = new GovernanceDAO(address(usdc), RATE, PERIOD);
        assertEq(dao6.tokenUnit(), 1e6);
    }

    /* Test for revert on rate, address token 0 and period */
    function test_Constructor_RevertsOnZeroRate() public {
        vm.expectRevert(
            abi.encodeWithSelector(GovernanceDAO.InvalidConstructorArguments.selector, address(token), 0, PERIOD)
        );
        new GovernanceDAO(address(token), 0, PERIOD);
    }

    function test_Constructor_RevertsOnZeroToken() public {
        vm.expectRevert(abi.encodeWithSelector(GovernanceDAO.InvalidConstructorArguments.selector, 0, RATE, PERIOD));
        new GovernanceDAO(address(0), RATE, PERIOD);
    }

    function test_Constructor_RevertsOnZeroPeriod() public {
        vm.expectRevert(
            abi.encodeWithSelector(GovernanceDAO.InvalidConstructorArguments.selector, address(token), RATE, 0)
        );
        new GovernanceDAO(address(token), RATE, 0);
    }

    /* buyShares tests for low amount, exact amount and rounded up cost */
    function test_BuyShares_RevertsOnLowAmount() public {
        uint256 amount = 1;
        vm.expectRevert(abi.encodeWithSelector(GovernanceDAO.AmountTooLow.selector, amount));
        dao.buyShares(amount);
    }

    function test_BuyShares_ExactAmount() public {
        mintAndBuy(alice);
        assertEq(dao.shares(alice), 10); /* Mapping registered 10 shares for alice? */
        assertEq(dao.totalShares(), 10); /* totalShares is updated? */
        assertEq(token.balanceOf(address(dao)), 1e18); /* is contract's balance updated? */
        assertEq(token.balanceOf(alice), 0); /* is alice's balance updated? */
    }

    function test_BuyShares_RoundsCostUp() public {
        MockERC20 usdc = new MockERC20(6); /* tokenUnit = 1e6 */
        GovernanceDAO dao6 = new GovernanceDAO(address(usdc), 3, PERIOD);

        usdc.mint(alice, 1_500_000); /* Create alice balance 1_500_000 base units (1,5 Token) */

        /*
            Expected values:
            shares = 1_500_000 * 3 / 1e6 = 4,5 rounded 4
            cost = ceil(4 * 1e6 / 3) = 1_333_334
        */

        vm.prank(alice);
        usdc.approve(address(dao6), 1_500_000);
        vm.prank(alice);
        dao6.buyShares(1_500_000);

        assertEq(dao6.shares(alice), 4);
        assertEq(dao6.totalShares(), 4);
        assertEq(usdc.balanceOf(address(dao6)), 1_333_334);
        assertEq(usdc.balanceOf(alice), 166_666);
    }

    function test_CloseSales_UnauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        dao.closeSales();
    }

    function test_CloseSales_FlagChange() public {
        assertTrue(dao.salesOpen());
        dao.closeSales();
        assertFalse(dao.salesOpen());
    }

    function test_CloseSales_EmitEvent() public {
        vm.expectEmit(address(dao));
        emit SalesClosed();
        dao.closeSales();
    }

    function test_CloseSales_SaleIsAlreadyClosed() public {
        dao.closeSales();
        vm.expectRevert(GovernanceDAO.SaleIsAlreadyClosed.selector);
        dao.closeSales();
    }

    function test_BuyShares_SaleIsClosed() public {
        dao.closeSales();
        vm.prank(alice);
        vm.expectRevert(GovernanceDAO.SaleIsClosed.selector);
        dao.buyShares(1e18);
    }

    function test_CreateProposal_ProposalCreated() public {
        mintAndBuy(alice);

        dao.closeSales();

        /* Expected indipendent value: blocktime + PERIOD */
        uint64 expectedEnd = uint64(block.timestamp + PERIOD);

        /* 1) Expected event: 2 indexed topics (true), compare data (true) */
        vm.expectEmit(true, true, false, true);
        /* 2) Declare how event is expected to emit */
        emit ProposalCreated(1, alice, expectedEnd, "Hello", "world!");

        /* 3) Alice makes the real call */
        vm.prank(alice);
        dao.createProposal("Hello", "world!");

        assertEq(dao.proposalCount(), 1);
    }

    function test_CreateProposal_SalesNotClosed() public {
        mintAndBuy(alice);

        vm.expectRevert(GovernanceDAO.SalesStageNotEnded.selector);
        vm.prank(alice);
        dao.createProposal("Hello", "world!");
    }

    function test_CreateProposal_CallerHasNoShares() public {
        dao.closeSales();
        vm.expectRevert(abi.encodeWithSelector(GovernanceDAO.UserMustBeShareholder.selector, 0));
        vm.prank(alice);
        dao.createProposal("Hello", "world!");
    }

    function test_CreateProposal_DifferentIdsForSubsequentProposals() public {
        mintAndBuy(alice);
        mintAndBuy(bob);

        dao.closeSales();

        uint64 expectedEnd = uint64(block.timestamp + PERIOD);

        vm.expectEmit(true, true, false, true);
        emit ProposalCreated(1, alice, expectedEnd, "Hello", "world!");

        vm.prank(alice);
        dao.createProposal("Hello", "world!");

        vm.expectEmit(true, true, false, true);
        emit ProposalCreated(2, bob, expectedEnd, "Test", "just another proposal");

        vm.prank(bob);
        dao.createProposal("Test", "just another proposal");

        assertEq(dao.proposalCount(), 2);
    }
}
