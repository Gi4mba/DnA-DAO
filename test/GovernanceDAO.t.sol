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
    address joe;

    uint256 constant RATE = 10;
    uint256 constant PERIOD = 7 days;

    event SalesClosed();
    event ProposalCreated(
        uint256 indexed id, address indexed proposer, uint64 endTime, string title, string description
    );
    event Voted(uint256 indexed id, address indexed voter, GovernanceDAO.VoteType choice, uint256 weight);

    /* SetUp() starts from a fresh new contract */
    function setUp() public {
        token = new MockERC20(18);
        dao = new GovernanceDAO(address(token), RATE, PERIOD);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        joe = makeAddr("joe");
    }

    function mintAndBuy(address caller) internal {
        token.mint(caller, 1e18); /* MockERC20 can mint tokens */
        vm.prank(caller); /* NEXT call has msg.sender = alice */
        token.approve(address(dao), 1e18);
        vm.prank(caller);
        dao.buyShares(1e18);
    }

    function mintBuyAndCreateProposal(address caller) internal {
        mintAndBuy(caller);
        dao.closeSales();

        vm.prank(caller);
        dao.createProposal("Make", "coffee");
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

    function test_Vote_Success() public {
        mintBuyAndCreateProposal(alice);

        assertFalse(dao.hasVoted(1, alice));

        vm.expectEmit(true, true, false, true);
        emit Voted(1, alice, GovernanceDAO.VoteType.For, 10);
        vm.prank(alice);
        dao.vote(1, GovernanceDAO.VoteType.For);

        assertTrue(dao.hasVoted(1, alice));
    }

    function test_Vote_RevertsOnZeroShares() public {
        mintBuyAndCreateProposal(bob);

        vm.expectRevert(abi.encodeWithSelector(GovernanceDAO.UserMustBeShareholder.selector, 0));
        vm.prank(alice);
        dao.vote(1, GovernanceDAO.VoteType.For);
    }

    function test_Vote_RevertsOnDoubleVoting() public {
        mintBuyAndCreateProposal(alice);

        vm.prank(alice);
        dao.vote(1, GovernanceDAO.VoteType.For);

        vm.expectRevert(GovernanceDAO.ProposalAlreadyVoted.selector);
        vm.prank(alice);
        dao.vote(1, GovernanceDAO.VoteType.Against);
    }

    function test_Vote_SuccessOnExactExpiration() public {
        mintBuyAndCreateProposal(alice);

        /* `vm.warp()` manipulates block.timestamp, modifying simulation's state, not code. */
        vm.warp(block.timestamp + PERIOD);

        vm.expectEmit(true, true, false, true);
        emit Voted(1, alice, GovernanceDAO.VoteType.Abstain, 10);
        vm.prank(alice);
        dao.vote(1, GovernanceDAO.VoteType.Abstain);
    }

    function test_Vote_RevertsOnExpiration() public {
        mintBuyAndCreateProposal(alice);

        uint64 expectedEnd = uint64(vm.getBlockTimestamp() + PERIOD);
        vm.warp(expectedEnd + 1);

        vm.expectRevert(abi.encodeWithSelector(GovernanceDAO.ProposalExpired.selector, expectedEnd));
        vm.prank(alice);
        dao.vote(1, GovernanceDAO.VoteType.Abstain);
    }

    function test_Vote_RevertsOnInvalidId() public {
        mintAndBuy(alice);
        mintAndBuy(bob);

        dao.closeSales();

        vm.prank(alice);
        dao.createProposal("Hello", "world!");
        vm.prank(bob);
        dao.createProposal("Just", "another proposal");

        uint256 _zeroId = 0;
        vm.expectRevert(abi.encodeWithSelector(GovernanceDAO.InvalidProposalId.selector, _zeroId));
        vm.prank(alice);
        dao.vote(_zeroId, GovernanceDAO.VoteType.For);

        uint256 _idBeyondCount = 3;
        vm.expectRevert(abi.encodeWithSelector(GovernanceDAO.InvalidProposalId.selector, _idBeyondCount));
        vm.prank(bob);
        dao.vote(_idBeyondCount, GovernanceDAO.VoteType.Against);
    }

    function test_Vote_RevertsOnInvalidVoteType() public {
        mintBuyAndCreateProposal(alice);

        /* Low-level call encodes _wrongVoteType in the vote function
        @params = id, VoteType */
        uint256 _wrongVoteType = 3;
        bytes memory wrongCalldataVoteType = abi.encodeWithSelector(dao.vote.selector, 1, _wrongVoteType);

        vm.prank(alice);
        /* Saves call response (success, response) in thwo different variables */
        (bool wSuccess, bytes memory wResponse) = address(dao).call(wrongCalldataVoteType);

        assertFalse(wSuccess); // `success` is false: contract rejected the encoded invalid VoteType 3
        assertEq(wResponse.length, 0); // `response` length is 0: rejection carries no response nor error names.

        uint256 _rightVoteType = 2;
        bytes memory rightCalldataVoteType = abi.encodeWithSelector(dao.vote.selector, 1, _rightVoteType);

        vm.prank(alice);
        (bool rSuccess,) = address(dao).call(rightCalldataVoteType);

        assertTrue(rSuccess);
    }

    function test_Status_RevertsOnInvalidId() public {
        mintAndBuy(alice);
        mintAndBuy(bob);

        dao.closeSales();

        vm.prank(alice);
        dao.createProposal("Hello", "world!");
        vm.prank(bob);
        dao.createProposal("Just", "another proposal");

        uint256 _zeroId = 0;
        vm.expectRevert(abi.encodeWithSelector(GovernanceDAO.InvalidProposalId.selector, _zeroId));
        vm.prank(alice);
        dao.status(_zeroId);

        uint256 _idBeyondCount = 3;
        vm.expectRevert(abi.encodeWithSelector(GovernanceDAO.InvalidProposalId.selector, _idBeyondCount));
        vm.prank(bob);
        dao.status(_idBeyondCount);
    }

    function test_Status_VotingIsPending() public {
        mintBuyAndCreateProposal(alice);

        uint64 expectedEnd = uint64(vm.getBlockTimestamp() + PERIOD);
        vm.warp(expectedEnd);

        GovernanceDAO.Status result = dao.status(1);
        assertEq(uint256(result), uint256(GovernanceDAO.Status.Pending));
    }

    /* For 40 shares, Bob (60) does not vote. Quorum is exactly 40% */
    function test_Status_Approved() public {
        token.mint(alice, 4e18);
        vm.prank(alice);
        token.approve(address(dao), 4e18);
        vm.prank(alice);
        dao.buyShares(4e18);

        token.mint(bob, 6e18);
        vm.prank(bob);
        token.approve(address(dao), 6e18);
        vm.prank(bob);
        dao.buyShares(6e18);

        dao.closeSales();

        vm.prank(alice);
        dao.createProposal("Make", "coffee");

        vm.prank(alice);
        dao.vote(1, GovernanceDAO.VoteType.For);

        uint64 expectedEnd = uint64(vm.getBlockTimestamp() + PERIOD);
        vm.warp(expectedEnd + 1);

        GovernanceDAO.Status result = dao.status(1);
        assertEq(uint256(result), uint256(GovernanceDAO.Status.Approved));
    }

    /* For 11 shares, Against 10 shares, Abstained 3 shares. Abstained do not count for approval */
    function test_Status_ApprovedWithAbstained() public {
        mintAndBuy(alice);

        token.mint(bob, 1.1e18);
        vm.prank(bob);
        token.approve(address(dao), 1.1e18);
        vm.prank(bob);
        dao.buyShares(1.1e18);

        token.mint(joe, 3e17);
        vm.prank(joe);
        token.approve(address(dao), 3e17);
        vm.prank(joe);
        dao.buyShares(3e17);

        dao.closeSales();

        vm.prank(alice);
        dao.createProposal("Make", "coffee");

        vm.prank(alice);
        dao.vote(1, GovernanceDAO.VoteType.Against);

        vm.prank(bob);
        dao.vote(1, GovernanceDAO.VoteType.For);

        vm.prank(joe);
        dao.vote(1, GovernanceDAO.VoteType.Abstain);

        uint64 expectedEnd = uint64(vm.getBlockTimestamp() + PERIOD);
        vm.warp(expectedEnd + 1);

        GovernanceDAO.Status result = dao.status(1);
        assertEq(uint256(result), uint256(GovernanceDAO.Status.Approved));
    }

    /* For 10 shares, Against 10 shares. Tie is Rejected */
    function test_Status_TieRejected() public {
        mintAndBuy(bob);
        mintBuyAndCreateProposal(alice);

        vm.prank(alice);
        dao.vote(1, GovernanceDAO.VoteType.For);
        vm.prank(bob);
        dao.vote(1, GovernanceDAO.VoteType.Against);

        uint64 expectedEnd = uint64(vm.getBlockTimestamp() + PERIOD);
        vm.warp(expectedEnd + 1);

        GovernanceDAO.Status result = dao.status(1);
        assertEq(uint256(result), uint256(GovernanceDAO.Status.Rejected));
    }

    /* 11 For vs 10 Against: one share above the tie, strict majority of For + Against */
    function test_Status_ApprovedByOneShare() public {
        token.mint(alice, 1.1e18);
        vm.prank(alice);
        token.approve(address(dao), 1.1e18);
        vm.prank(alice);
        dao.buyShares(1.1e18);

        mintBuyAndCreateProposal(bob);

        vm.prank(alice);
        dao.vote(1, GovernanceDAO.VoteType.For);
        vm.prank(bob);
        dao.vote(1, GovernanceDAO.VoteType.Against);

        uint64 expectedEnd = uint64(vm.getBlockTimestamp() + PERIOD);
        vm.warp(expectedEnd + 1);

        GovernanceDAO.Status result = dao.status(1);
        assertEq(uint256(result), uint256(GovernanceDAO.Status.Approved));
    }

    /* Quorum reached with abstentions only: no For votes. Rejected */
    function test_Status_RejectedWhenAllAbstain() public {
        mintAndBuy(bob);
        mintBuyAndCreateProposal(alice);

        vm.prank(alice);
        dao.vote(1, GovernanceDAO.VoteType.Abstain);
        vm.prank(bob);
        dao.vote(1, GovernanceDAO.VoteType.Abstain);

        uint64 expectedEnd = uint64(vm.getBlockTimestamp() + PERIOD);
        vm.warp(expectedEnd + 1);

        GovernanceDAO.Status result = dao.status(1);
        assertEq(uint256(result), uint256(GovernanceDAO.Status.Rejected));
    }

    /* Quorum boundary, below side: 39%, just under 40% threshold. Inclusive side (40%) is covered by test_Status_Approved */
    function test_Status_QuorumNotReached() public {
        token.mint(alice, 3.9e18);
        vm.prank(alice);
        token.approve(address(dao), 3.9e18);
        vm.prank(alice);
        dao.buyShares(3.9e18);

        token.mint(bob, 6.1e18);
        vm.prank(bob);
        token.approve(address(dao), 6.1e18);
        vm.prank(bob);
        dao.buyShares(6.1e18);

        dao.closeSales();

        vm.prank(alice);
        dao.createProposal("Make", "coffee");

        vm.prank(alice);
        dao.vote(1, GovernanceDAO.VoteType.For);

        uint64 expectedEnd = uint64(vm.getBlockTimestamp() + PERIOD);
        vm.warp(expectedEnd + 1);

        GovernanceDAO.Status result = dao.status(1);
        assertEq(uint256(result), uint256(GovernanceDAO.Status.QuorumNotReached));
    }

    /* Quorum boundary, below side: totalShares is 7. 2 shares (28.6%) must not reach quorum.
        Integer division would round threshold down to 2 letting them reach quorum */
    function test_Status_QuorumNotReachedWhenThresholdHasRemainder() public {
        token.mint(alice, 2e17);
        vm.prank(alice);
        token.approve(address(dao), 2e17);
        vm.prank(alice);
        dao.buyShares(2e17);

        token.mint(bob, 5e17);
        vm.prank(bob);
        token.approve(address(dao), 5e17);
        vm.prank(bob);
        dao.buyShares(5e17);

        dao.closeSales();

        vm.prank(bob);
        dao.createProposal("Make", "coffee");

        vm.prank(alice);
        dao.vote(1, GovernanceDAO.VoteType.For);

        uint64 expectedEnd = uint64(vm.getBlockTimestamp() + PERIOD);
        vm.warp(expectedEnd + 1);

        GovernanceDAO.Status result = dao.status(1);
        assertEq(uint256(result), uint256(GovernanceDAO.Status.QuorumNotReached));
    }

    /* Quorum boundary, above side: totalShares is 7. 3 shares (42.9%) is the smallest
        integer amount reaching quorum */
    function test_Status_QuorumReachedWhenThresholdHasRemainder() public {
        token.mint(alice, 3e17);
        vm.prank(alice);
        token.approve(address(dao), 3e17);
        vm.prank(alice);
        dao.buyShares(3e17);

        token.mint(bob, 4e17);
        vm.prank(bob);
        token.approve(address(dao), 4e17);
        vm.prank(bob);
        dao.buyShares(4e17);

        dao.closeSales();

        vm.prank(bob);
        dao.createProposal("Make", "coffee");

        vm.prank(alice);
        dao.vote(1, GovernanceDAO.VoteType.For);

        uint64 expectedEnd = uint64(vm.getBlockTimestamp() + PERIOD);
        vm.warp(expectedEnd + 1);

        GovernanceDAO.Status result = dao.status(1);
        assertEq(uint256(result), uint256(GovernanceDAO.Status.Approved));
    }
}
