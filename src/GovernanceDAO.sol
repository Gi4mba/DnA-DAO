// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract GovernanceDAO is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20Metadata;
    // Types
    enum VoteType {
        For,
        Against,
        Abstain
    }
    enum Status {
        Pending,
        Approved,
        Rejected,
        QuorumNotReached
    }

    struct Proposal {
        address proposer; // 20 byte
        uint64 endTime; // 8 byte
        uint256 forShares;
        uint256 againstShares;
        uint256 abstainShares;
        string description;
    }

    // Immutables
    IERC20Metadata public immutable token;
    uint256 public immutable exchangeRate;
    uint256 public immutable votingPeriod;
    uint256 public immutable tokenUnit;

    // State: members & actions
    bool public salesOpen = true;
    mapping(address => uint256) public shares;
    uint256 public totalShares;

    // State: proposals & votes
    uint256 public proposalCount;
    mapping(uint256 => Proposal) internal _proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    // Errors
    error InvalidConstructorArguments(address _token, uint256 _exchangeRate, uint256 _votingPeriod);
    error AmountTooLow(uint256 _amount);

    // Events
    event SharesPurchased(address indexed buyer, uint256 sharesBought, uint256 cost);
    event SalesClosed();
    event ProposalCreated(uint256 indexed id, address indexed proposer, uint64 endtime, string description);
    event Voted(uint256 indexed id, address indexed voter, VoteType choice, uint256 weight);

    constructor(address _token, uint256 _exchangeRate, uint256 _votingPeriod) Ownable(msg.sender) {
        if (_token == address(0) || _exchangeRate == 0 || _votingPeriod == 0) {
            revert InvalidConstructorArguments(_token, _exchangeRate, _votingPeriod);
        }

        token = IERC20Metadata(_token);
        exchangeRate = _exchangeRate;
        votingPeriod = _votingPeriod;
        tokenUnit = 10 ** IERC20Metadata(_token).decimals();
    }

    function buyShares(uint256 _amount) external nonReentrant {
        uint256 newShares = _amount * exchangeRate / tokenUnit;
        if (newShares == 0) {
            revert AmountTooLow(_amount);
        }
        // flooring newShares is an expected behaviour: cost is calculated on whole shares.
        // forge-lint: disable-next-line(divide-before-multiply)
        uint256 cost = (newShares * tokenUnit + exchangeRate - 1) / exchangeRate;

        shares[msg.sender] += newShares;
        totalShares += newShares;
        token.safeTransferFrom(msg.sender, address(this), cost);

        emit SharesPurchased(msg.sender, newShares, cost);
    }
}
