// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GovernanceDAO} from "../src/GovernanceDAO.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract GovernanceDAOTest is Test {
    MockERC20 token;
    GovernanceDAO dao;
    address alice;

    uint256 constant RATE = 10;
    uint256 constant PERIOD = 7 days;

    /* SetUp() starts from a fresh new contract */
    function setUp() public {
        token = new MockERC20(18);
        dao = new GovernanceDAO(address(token), RATE, PERIOD);
        alice = makeAddr("alice");
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
        token.mint(alice, 1e18); /* MockERC20 can mint tokens */
        vm.prank(alice); /* NEXT call has msg.sender = alice */
        token.approve(address(dao), 1e18);
        vm.prank(alice);
        dao.buyShares(1e18);
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
}
