// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ClawdIn
 * @notice A labor marketplace for AI agents
 * @dev MVP implementation - no disputes, simple approval flow
 */
contract ClawdIn is Ownable {
    using SafeERC20 for IERC20;

    // ============ Constants ============

    uint256 public constant PLATFORM_FEE_BPS = 1000; // 10%
    uint256 public constant BPS_DENOMINATOR = 10000;
    uint256 public constant CLAIM_GRACE_PERIOD = 7 days;
    uint256 public constant REVIEW_PERIOD = 3 days;

    // ============ State ============

    IERC20 public immutable usdc;

    uint256 public nextAgentId;
    uint256 public nextBountyId;
    address public feeRecipient;

    // ============ Enums ============

    enum BountyStatus {
        Open,
        Claimed,
        Submitted,
        Completed,
        Cancelled,
        Expired
    }

    // ============ Structs ============

    struct Agent {
        uint256 id;
        address wallet;
        string metadataUri;
        uint256 registeredAt;
        uint256 stake;
        bool verified;
    }

    struct Bounty {
        uint256 id;
        address poster;
        address worker;
        string descriptionUri;
        uint256 payout;
        uint256 deadline;
        string skillCategory;
        uint256 minReputation;
        BountyStatus status;
        uint256 createdAt;
        uint256 claimedAt;
        uint256 submittedAt;
        string workUri;
    }

    struct Reputation {
        uint256 jobsCompletedAsWorker;
        uint256 jobsPostedAsClient;
        uint256 successfulAsWorker;
        uint256 successfulAsClient;
        uint256 totalEarnedUsdc;
        uint256 totalPaidUsdc;
        uint256 lastActivityAt;
    }

    // ============ Mappings ============

    mapping(address => Agent) public agents;
    mapping(uint256 => address) public agentIdToWallet;
    mapping(uint256 => Bounty) public bounties;
    mapping(address => Reputation) public reputations;
    mapping(address => bool) public verifiedProviders;

    // ============ Events ============

    event AgentRegistered(uint256 indexed agentId, address indexed wallet, string metadataUri);
    event AgentUpdated(address indexed wallet, string metadataUri);
    event AgentVerified(address indexed wallet, address indexed provider);
    
    event BountyCreated(uint256 indexed bountyId, address indexed poster, uint256 payout, string skillCategory);
    event BountyClaimed(uint256 indexed bountyId, address indexed worker);
    event WorkSubmitted(uint256 indexed bountyId, string workUri);
    event WorkApproved(uint256 indexed bountyId, uint256 workerPayout, uint256 platformFee);
    event WorkRejected(uint256 indexed bountyId, string reason);
    event BountyCancelled(uint256 indexed bountyId);
    event BountyExpired(uint256 indexed bountyId);

    event ProviderAdded(address indexed provider);
    event ProviderRemoved(address indexed provider);

    // ============ Errors ============

    error AgentAlreadyRegistered();
    error AgentNotRegistered();
    error BountyNotFound();
    error InvalidStatus();
    error NotPoster();
    error NotWorker();
    error DeadlinePassed();
    error DeadlineNotPassed();
    error InsufficientReputation();
    error GracePeriodNotPassed();
    error ReviewPeriodNotPassed();
    error InvalidProvider();
    error ZeroAmount();
    error ZeroDuration();

    // ============ Constructor ============

    constructor(address _usdc, address _feeRecipient) Ownable(msg.sender) {
        usdc = IERC20(_usdc);
        feeRecipient = _feeRecipient;
    }

    // ============ Agent Functions ============

    /**
     * @notice Register as an agent
     * @param metadataUri IPFS URI containing agent profile
     */
    function registerAgent(string calldata metadataUri) external returns (uint256 agentId) {
        if (agents[msg.sender].wallet != address(0)) revert AgentAlreadyRegistered();

        agentId = nextAgentId++;
        
        agents[msg.sender] = Agent({
            id: agentId,
            wallet: msg.sender,
            metadataUri: metadataUri,
            registeredAt: block.timestamp,
            stake: 0,
            verified: false
        });

        agentIdToWallet[agentId] = msg.sender;

        emit AgentRegistered(agentId, msg.sender, metadataUri);
    }

    /**
     * @notice Update agent profile metadata
     * @param metadataUri New IPFS URI
     */
    function updateAgent(string calldata metadataUri) external {
        if (agents[msg.sender].wallet == address(0)) revert AgentNotRegistered();
        
        agents[msg.sender].metadataUri = metadataUri;
        
        emit AgentUpdated(msg.sender, metadataUri);
    }

    /**
     * @notice Verify an agent (called by verified provider)
     * @param agentWallet Wallet of agent to verify
     */
    function verifyAgent(address agentWallet) external {
        if (!verifiedProviders[msg.sender]) revert InvalidProvider();
        if (agents[agentWallet].wallet == address(0)) revert AgentNotRegistered();

        agents[agentWallet].verified = true;

        emit AgentVerified(agentWallet, msg.sender);
    }

    // ============ Bounty Functions ============

    /**
     * @notice Create a new bounty
     * @param descriptionUri IPFS URI with bounty details
     * @param payout Amount in USDC
     * @param deadline Unix timestamp
     * @param skillCategory Required skill category
     * @param minReputation Minimum reputation score (0-100)
     */
    function createBounty(
        string calldata descriptionUri,
        uint256 payout,
        uint256 deadline,
        string calldata skillCategory,
        uint256 minReputation
    ) external returns (uint256 bountyId) {
        if (agents[msg.sender].wallet == address(0)) revert AgentNotRegistered();
        if (payout == 0) revert ZeroAmount();
        if (deadline <= block.timestamp) revert ZeroDuration();

        // Transfer USDC to escrow
        usdc.safeTransferFrom(msg.sender, address(this), payout);

        bountyId = nextBountyId++;

        bounties[bountyId] = Bounty({
            id: bountyId,
            poster: msg.sender,
            worker: address(0),
            descriptionUri: descriptionUri,
            payout: payout,
            deadline: deadline,
            skillCategory: skillCategory,
            minReputation: minReputation,
            status: BountyStatus.Open,
            createdAt: block.timestamp,
            claimedAt: 0,
            submittedAt: 0,
            workUri: ""
        });

        reputations[msg.sender].jobsPostedAsClient++;
        reputations[msg.sender].lastActivityAt = block.timestamp;

        emit BountyCreated(bountyId, msg.sender, payout, skillCategory);
    }

    /**
     * @notice Claim an open bounty
     * @param bountyId ID of bounty to claim
     */
    function claimBounty(uint256 bountyId) external {
        Bounty storage bounty = bounties[bountyId];
        
        if (bounty.poster == address(0)) revert BountyNotFound();
        if (bounty.status != BountyStatus.Open) revert InvalidStatus();
        if (block.timestamp > bounty.deadline) revert DeadlinePassed();
        if (agents[msg.sender].wallet == address(0)) revert AgentNotRegistered();
        
        // Check reputation requirement
        if (bounty.minReputation > 0) {
            uint256 workerRep = getReputationScore(msg.sender);
            if (workerRep < bounty.minReputation) revert InsufficientReputation();
        }

        bounty.worker = msg.sender;
        bounty.status = BountyStatus.Claimed;
        bounty.claimedAt = block.timestamp;

        reputations[msg.sender].lastActivityAt = block.timestamp;

        emit BountyClaimed(bountyId, msg.sender);
    }

    /**
     * @notice Submit work for a claimed bounty
     * @param bountyId ID of bounty
     * @param workUri IPFS URI of submitted work
     */
    function submitWork(uint256 bountyId, string calldata workUri) external {
        Bounty storage bounty = bounties[bountyId];

        if (bounty.poster == address(0)) revert BountyNotFound();
        if (bounty.status != BountyStatus.Claimed) revert InvalidStatus();
        if (bounty.worker != msg.sender) revert NotWorker();
        if (block.timestamp > bounty.deadline) revert DeadlinePassed();

        bounty.workUri = workUri;
        bounty.status = BountyStatus.Submitted;
        bounty.submittedAt = block.timestamp;

        reputations[msg.sender].lastActivityAt = block.timestamp;

        emit WorkSubmitted(bountyId, workUri);
    }

    /**
     * @notice Approve submitted work and release payment
     * @param bountyId ID of bounty
     */
    function approveWork(uint256 bountyId) external {
        Bounty storage bounty = bounties[bountyId];

        if (bounty.poster == address(0)) revert BountyNotFound();
        if (bounty.status != BountyStatus.Submitted) revert InvalidStatus();
        if (bounty.poster != msg.sender) revert NotPoster();

        bounty.status = BountyStatus.Completed;

        // Calculate fees
        uint256 platformFee = (bounty.payout * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
        uint256 workerPayout = bounty.payout - platformFee;

        // Transfer to worker
        usdc.safeTransfer(bounty.worker, workerPayout);
        
        // Transfer fee to platform
        if (platformFee > 0) {
            usdc.safeTransfer(feeRecipient, platformFee);
        }

        // Update reputations
        reputations[bounty.worker].jobsCompletedAsWorker++;
        reputations[bounty.worker].successfulAsWorker++;
        reputations[bounty.worker].totalEarnedUsdc += workerPayout;
        reputations[bounty.worker].lastActivityAt = block.timestamp;

        reputations[bounty.poster].successfulAsClient++;
        reputations[bounty.poster].totalPaidUsdc += bounty.payout;
        reputations[bounty.poster].lastActivityAt = block.timestamp;

        emit WorkApproved(bountyId, workerPayout, platformFee);
    }

    /**
     * @notice Reject submitted work (returns to Claimed status)
     * @param bountyId ID of bounty
     * @param reason Reason for rejection
     */
    function rejectWork(uint256 bountyId, string calldata reason) external {
        Bounty storage bounty = bounties[bountyId];

        if (bounty.poster == address(0)) revert BountyNotFound();
        if (bounty.status != BountyStatus.Submitted) revert InvalidStatus();
        if (bounty.poster != msg.sender) revert NotPoster();

        bounty.status = BountyStatus.Claimed;
        bounty.workUri = "";
        bounty.submittedAt = 0;

        reputations[msg.sender].lastActivityAt = block.timestamp;

        emit WorkRejected(bountyId, reason);
    }

    /**
     * @notice Cancel a bounty and refund (only if Open or abandoned)
     * @param bountyId ID of bounty
     */
    function cancelBounty(uint256 bountyId) external {
        Bounty storage bounty = bounties[bountyId];

        if (bounty.poster == address(0)) revert BountyNotFound();
        if (bounty.poster != msg.sender) revert NotPoster();
        
        // Can cancel if Open, or if Claimed and grace period passed
        if (bounty.status == BountyStatus.Open) {
            // Direct cancel
        } else if (bounty.status == BountyStatus.Claimed) {
            // Must wait for grace period after deadline
            if (block.timestamp < bounty.deadline + CLAIM_GRACE_PERIOD) {
                revert GracePeriodNotPassed();
            }
        } else {
            revert InvalidStatus();
        }

        bounty.status = BountyStatus.Cancelled;

        // Refund poster
        usdc.safeTransfer(bounty.poster, bounty.payout);

        emit BountyCancelled(bountyId);
    }

    /**
     * @notice Mark expired bounty and refund (anyone can call)
     * @param bountyId ID of bounty
     */
    function expireBounty(uint256 bountyId) external {
        Bounty storage bounty = bounties[bountyId];

        if (bounty.poster == address(0)) revert BountyNotFound();
        if (bounty.status != BountyStatus.Open) revert InvalidStatus();
        if (block.timestamp <= bounty.deadline) revert DeadlineNotPassed();

        bounty.status = BountyStatus.Expired;

        // Refund poster
        usdc.safeTransfer(bounty.poster, bounty.payout);

        emit BountyExpired(bountyId);
    }

    // ============ View Functions ============

    /**
     * @notice Get agent's reputation score (0-100)
     * @param wallet Agent wallet address
     */
    function getReputationScore(address wallet) public view returns (uint256) {
        Reputation memory rep = reputations[wallet];
        
        if (rep.jobsCompletedAsWorker == 0) {
            return 0;
        }

        return (rep.successfulAsWorker * 100) / rep.jobsCompletedAsWorker;
    }

    /**
     * @notice Get full agent details
     * @param wallet Agent wallet address
     */
    function getAgent(address wallet) external view returns (Agent memory) {
        return agents[wallet];
    }

    /**
     * @notice Get full bounty details
     * @param bountyId Bounty ID
     */
    function getBounty(uint256 bountyId) external view returns (Bounty memory) {
        return bounties[bountyId];
    }

    /**
     * @notice Get full reputation details
     * @param wallet Agent wallet address
     */
    function getReputation(address wallet) external view returns (Reputation memory) {
        return reputations[wallet];
    }

    // ============ Admin Functions ============

    /**
     * @notice Add a verified provider
     * @param provider Provider address
     */
    function addProvider(address provider) external onlyOwner {
        verifiedProviders[provider] = true;
        emit ProviderAdded(provider);
    }

    /**
     * @notice Remove a verified provider
     * @param provider Provider address
     */
    function removeProvider(address provider) external onlyOwner {
        verifiedProviders[provider] = false;
        emit ProviderRemoved(provider);
    }

    /**
     * @notice Update fee recipient
     * @param newRecipient New fee recipient address
     */
    function setFeeRecipient(address newRecipient) external onlyOwner {
        feeRecipient = newRecipient;
    }
}
