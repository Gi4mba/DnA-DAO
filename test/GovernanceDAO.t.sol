// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GovernanceDAO} from "../src/GovernanceDAO.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract GovernanceDAOTest is Test {
    MockERC20 token;
    GovernanceDAO dao;

    uint256 constant RATE = 10;
    uint256 constant PERIOD = 7 days;

    /* SetUp() parte da un contratto pulito */
    function setUp() public {
        token = new MockERC20(18);
        dao = new GovernanceDAO(address(token), RATE, PERIOD);
        address alice = makeAddr("alice");
    }

    /* Test verifica che i valori salvati coincidano con quelli passati */
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

    /* Test su token con 6 decimali */
    function test_Constructor_TokenUnitWith6Decimals() public {
        MockERC20 usdc = new MockERC20(6);
        GovernanceDAO dao6 = new GovernanceDAO(address(usdc), RATE, PERIOD);
        assertEq(dao6.tokenUnit(), 1e6);
    }

    /* Test sui revert */
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

    /* Test per chiamare una funzione da un address differente da quello del contratto */
    /* --- Non ancora implementato:

    function test_CloseSales_RevertsIfNotOwner() public {
        vm.prank(alice); // PROSSIMA chiamata ha msg.sender = alice
        vm.expectRevert(); // ci aspettiamo che fallisca
        dao.closeSales();
    } --- */
}
