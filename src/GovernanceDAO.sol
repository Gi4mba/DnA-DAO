// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title GovernanceDAO
/// @notice Direct-democracy governance: members buy shares with an ERC-20 token, then vote on proposals.
/// @dev Two separate phases. While sales are open only `buyShares` works; after `closeSales` only proposals
/// and votes do, so `totalShares` is fixed during voting and no snapshot is needed. Proposals are a record
/// (text, aggregated votes, outcome): nothing is executed on-chain.
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
    error RenounceOwnershipIsDisabled();
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
    error WithdrawalNotAllowedDuringSales();
    error RecipientMustBeAValidAddress();
    error AmountMustBeMoreThanZero();

    // Events
    event SharesPurchased(address indexed buyer, uint256 sharesBought, uint256 cost);
    event SalesClosed();
    event ProposalCreated(
        uint256 indexed id, address indexed proposer, uint64 endTime, string title, string description
    );
    event Voted(uint256 indexed id, address indexed voter, VoteType choice, uint256 weight);
    event WithdrawSuccessful(address indexed to, uint256 amount);

    modifier onlyValidId(uint256 _proposalId) {
        if (_proposalId == 0 || _proposalId > proposalCount) {
            revert InvalidProposalId(_proposalId);
        }
        _;
    }

    /// @param _token ERC-20 token used to pay for shares.
    /// @param _exchangeRate Shares received per whole token (`10**decimals` base units).
    /// @param _votingPeriod Voting duration in seconds, the same for every proposal.
    constructor(address _token, uint256 _exchangeRate, uint256 _votingPeriod) Ownable(msg.sender) {
        if (_token == address(0) || _exchangeRate == 0 || _votingPeriod == 0) {
            revert InvalidConstructorArguments(_token, _exchangeRate, _votingPeriod);
        }

        token = IERC20Metadata(_token);
        exchangeRate = _exchangeRate;
        votingPeriod = _votingPeriod;
        tokenUnit = 10 ** IERC20Metadata(_token).decimals();
    }

    function renounceOwnership() public view override onlyOwner {
        revert RenounceOwnershipIsDisabled();
    }

    /// @notice Buys whole shares with the DAO token while sales are open.
    /// @dev Shares are rounded down; only the cost of the shares actually bought is pulled (rounded up),
    /// the remainder stays with the caller. Requires prior token approval. Reverts if the amount buys 0 shares.
    /// @param _amount Maximum token amount, in base units, the caller is willing to spend.
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

    /// @notice Ends the sales phase and opens the proposal and voting phase.
    /// @dev Owner only and irreversible. Reverts if sales are already closed.
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

    /// @notice Creates a proposal; voting stays open for `votingPeriod` seconds.
    /// @dev Only after `closeSales`, only for shareholders. Ids start from 1. Title and description must be non-empty.
    /// @param _title Short title of the proposal.
    /// @param _description Full text of the proposal.
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

    /// @notice Votes on a proposal with all the shares owned by the caller.
    /// @dev One vote per address per proposal, not changeable. Voting is allowed up to and including `endTime`.
    /// Checks run in this order: shareholder, valid id, not expired, not already voted.
    /// @param _proposalId Id of the proposal.
    /// @param _choice For, Against or Abstain.
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

    function sumAllVotes(Proposal storage proposalRef) internal view returns (uint256 result) {
        result = proposalRef.forShares + proposalRef.againstShares + proposalRef.abstainShares;
    }

    function sumForAndAgainstVotes(Proposal storage proposalRef) internal view returns (uint256 result) {
        result = proposalRef.forShares + proposalRef.againstShares;
    }

    /// @notice Returns the state of a proposal: Pending, Approved, Rejected or QuorumNotReached.
    /// @dev Computed on demand, not stored. Pending until `endTime` included. Quorum: votes cast (for, against,
    /// abstain) must be at least 40% of `totalShares`. Approved only if For is strictly more than 50% of
    /// For + Against: a tie, or everyone abstaining with quorum reached, is Rejected. Integer math only.
    /// @param _proposalId Id of the proposal.
    function status(uint256 _proposalId) public view onlyValidId(_proposalId) returns (Status) {
        Proposal storage proposalRef = _proposals[_proposalId];

        // deadline check is intended: validators can shift block.timestamp only by seconds.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp <= proposalRef.endTime) {
            return Status.Pending;
        } else if (sumAllVotes(proposalRef) * 100 < quorum * totalShares) {
            return Status.QuorumNotReached;
        } else if (proposalRef.forShares * approvingThreshold <= sumForAndAgainstVotes(proposalRef)) {
            return Status.Rejected;
        } else {
            return Status.Approved;
        }
    }

    /// @notice Returns the full record of a proposal: proposer, end time, aggregated votes, title, description.
    /// @param _proposalId Id of the proposal.
    function viewProposal(uint256 _proposalId)
        external
        view
        onlyValidId(_proposalId)
        returns (Proposal memory proposal)
    {
        proposal = _proposals[_proposalId];
    }

    function withdraw(address _to, uint256 _amount) public onlyOwner {
        if (salesOpen) {
            revert WithdrawalNotAllowedDuringSales();
        }
        if (_to == address(0)) {
            revert RecipientMustBeAValidAddress();
        } else if (_amount == 0) {
            revert AmountMustBeMoreThanZero();
        }

        token.safeTransfer(_to, _amount);

        emit WithdrawSuccessful(_to, _amount);
    }
}
