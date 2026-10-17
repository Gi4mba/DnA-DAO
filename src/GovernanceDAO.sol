// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract GovernanceDAO is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20Metadata;
    using SafeCast for uint256;
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
        string title;
        string description;
    }

    // Immutables
    IERC20Metadata public immutable token;
    uint256 public immutable exchangeRate;
    uint256 public immutable votingPeriod;
    uint256 public immutable tokenUnit;
    uint256 public constant quorum = 40;
    uint256 public constant approvingThreshold = 2; // For * 2 > For + Against is the same as "more than 50%"

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
    error SaleIsClosed();
    error SaleIsAlreadyClosed();
    error SalesStageNotEnded();
    error UserMustBeShareholder(uint256 shares);
    error TitleIsEmpty(string _title);
    error DescriptionIsEmpty(string _description);
    error InvalidProposalId(uint256 _proposalId);
    error ProposalAlreadyVoted();
    error ProposalExpired(uint64 endTime);

    // Events
    event SharesPurchased(address indexed buyer, uint256 sharesBought, uint256 cost);
    event SalesClosed();
    event ProposalCreated(
        uint256 indexed id, address indexed proposer, uint64 endTime, string title, string description
    );
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
        if (salesOpen == false) {
            revert SaleIsClosed();
        }
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

    function closeSales() public onlyOwner {
        if (salesOpen == false) {
            revert SaleIsAlreadyClosed();
        }
        salesOpen = false;

        emit SalesClosed();
    }

    function currentStage() public view returns (string memory) {
        if (salesOpen == false) {
            return "Sales are closed";
        } else {
            return "Sales are open";
        }
    }

    function createProposal(string calldata _title, string calldata _description) external {
        if (salesOpen != false) {
            revert SalesStageNotEnded();
        }
        if (shares[msg.sender] == 0) {
            revert UserMustBeShareholder(shares[msg.sender]);
        }
        /* Converts _title and _description in bytes. Reverts if length's empty ("") */
        if (bytes(_title).length == 0) {
            revert TitleIsEmpty(_title);
        }
        if (bytes(_description).length == 0) {
            revert DescriptionIsEmpty(_description);
        }

        /* Converts expression in uint64, packing with proposer. Reduce gas per Proposal */
        uint64 _endTime = (block.timestamp + votingPeriod).toUint64();
        proposalCount++;

        /* Assignation: `Type Position Name = Constructor({value})` */
        Proposal memory newProposal = Proposal({
            proposer: msg.sender,
            endTime: _endTime,
            forShares: 0,
            againstShares: 0,
            abstainShares: 0,
            title: _title,
            description: _description
        });
        /* Calls mapping and saves newProposal to proposalCount slot */
        _proposals[proposalCount] = newProposal;

        emit ProposalCreated(proposalCount, msg.sender, _endTime, _title, _description);
    }

    function vote(uint256 _proposalId, VoteType _choice) external {
        /* salesOpen is set to false since proposals are being created and it's irreversible. Check not required */
        if (shares[msg.sender] == 0) {
            revert UserMustBeShareholder(shares[msg.sender]);
        }
        if (_proposalId == 0 || _proposalId > proposalCount) {
            revert InvalidProposalId(_proposalId);
        }
        // deadline check is intended: validators can shift block.timestamp only by seconds.
        // forge-lint: disable-next-line(block-timestamp)
        if ((block.timestamp) > _proposals[_proposalId].endTime) {
            revert ProposalExpired(_proposals[_proposalId].endTime);
        }
        if (hasVoted[_proposalId][msg.sender]) {
            revert ProposalAlreadyVoted();
        }

        hasVoted[_proposalId][msg.sender] = true;

        uint256 callerRawShares = shares[msg.sender];
        if (_choice == VoteType.For) {
            _proposals[_proposalId].forShares += callerRawShares;
        } else if (_choice == VoteType.Against) {
            _proposals[_proposalId].againstShares += callerRawShares;
        } else if (_choice == VoteType.Abstain) {
            _proposals[_proposalId].abstainShares += callerRawShares;
        }

        emit Voted(_proposalId, msg.sender, _choice, callerRawShares);
    }

    function sumAllVotes(uint256 _proposalId) internal view returns (uint256 result) {
        result = _proposals[_proposalId].forShares + _proposals[_proposalId].againstShares
            + _proposals[_proposalId].abstainShares;
    }

    function sumForAndAgainstVotes(uint256 _proposalId) internal view returns (uint256 result) {
        result = _proposals[_proposalId].forShares + _proposals[_proposalId].againstShares;
    }

    function status(uint256 _proposalId) public view returns (Status) {
        if (_proposalId == 0 || _proposalId > proposalCount) {
            revert InvalidProposalId(_proposalId);
        }

        // deadline check is intended: validators can shift block.timestamp only by seconds.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp <= _proposals[_proposalId].endTime) {
            return Status.Pending;
        } else if (sumAllVotes(_proposalId) * 100 < quorum * totalShares) {
            return Status.QuorumNotReached;
        } else if (_proposals[_proposalId].forShares * approvingThreshold <= sumForAndAgainstVotes(_proposalId)) {
            return Status.Rejected;
        } else {
            return Status.Approved;
        }
    }
}
