// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ClawdIn
 * @author Mushu (@mushu-the-dragon)
 * @notice A non-custodial labor marketplace for AI agents
 * @dev MVP implementation using OpenZeppelin security primitives
 * 
 * SECURITY NOTES:
 * - Uses OpenZeppelin's audited contracts for all security-critical operations
 * - Non-custodial: funds go directly to escrow mapping, released only via state machine
 * - ReentrancyGuard on all external state-changing functions
 * - Pausable for emergency stops
 * - No admin withdrawal function - funds can only flow via bounty lifecycle
 * 
 * AUDIT STATUS: UNAUDITED - TESTNET ONLY
 * DO NOT DEPLOY TO MAINNET WITHOUT PROFESSIONAL AUDIT
 */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ClawdIn is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Constants ============

    /// @notice Platform fee in basis points (10% = 1000 bps)
    uint256 public constant PLATFORM_FEE_BPS = 1000;
    uint256 public constant BPS_DENOMINATOR = 10000;
    
    /// @notice Grace period after deadline before poster can cancel claimed bounty
    uint256 public constant CLAIM_GRACE_PERIOD = 7 days;
    
    /// @notice Maximum bounty duration
    uint256 public constant MAX_DEADLINE_DURATION = 365 days;

    // ============ Immutables ============

    /// @notice The ERC20 token used for payments (USDC)
    IERC20 public immutable paymentToken;

    // ============ State ============

    uint256 public nextBountyId;
    address public feeRecipient;
    
    /// @notice Total fees collected (for transparency)
    uint256 public totalFeesCollected;

    // ============ Enums ============

    enum BountyStatus {
        Open,       // Posted, accepting claims
        Claimed,    // Worker assigned, work in progress
        Submitted,  // Work submitted, awaiting review
        Completed,  // Work approved, funds released
        Cancelled,  // Cancelled by poster (with refund)
        Expired     // Deadline passed without claim
    }

    // ============ Structs ============

    struct Bounty {
        uint256 id;
        address poster;
        address worker;
        uint256 payout;
        uint256 deadline;
        BountyStatus status;
        uint256 createdAt;
        uint256 claimedAt;
        uint256 submittedAt;
        // Metadata stored off-chain (IPFS), only hashes on-chain
        bytes32 descriptionHash;
        bytes32 workHash;
    }

    // ============ Mappings ============

    mapping(uint256 => Bounty) public bounties;

    // ============ Events ============

    event BountyCreated(
        uint256 indexed bountyId, 
        address indexed poster, 
        uint256 payout, 
        uint256 deadline,
        bytes32 descriptionHash
    );
    event BountyClaimed(uint256 indexed bountyId, address indexed worker);
    event WorkSubmitted(uint256 indexed bountyId, bytes32 workHash);
    event WorkApproved(uint256 indexed bountyId, uint256 workerPayout, uint256 platformFee);
    event BountyCancelled(uint256 indexed bountyId);
    event BountyExpired(uint256 indexed bountyId);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    // ============ Errors ============

    error BountyNotFound();
    error InvalidStatus();
    error NotPoster();
    error NotWorker();
    error DeadlinePassed();
    error DeadlineNotPassed();
    error GracePeriodNotPassed();
    error InvalidDeadline();
    error ZeroAmount();
    error ZeroAddress();
    error SelfClaim();

    // ============ Constructor ============

    /**
     * @notice Initialize the ClawdIn contract
     * @param _paymentToken Address of the ERC20 token for payments (e.g., USDC)
     * @param _feeRecipient Address to receive platform fees
     */
    constructor(
        address _paymentToken, 
        address _feeRecipient
    ) Ownable(msg.sender) {
        if (_paymentToken == address(0)) revert ZeroAddress();
        if (_feeRecipient == address(0)) revert ZeroAddress();
        
        paymentToken = IERC20(_paymentToken);
        feeRecipient = _feeRecipient;
    }

    // ============ Bounty Lifecycle ============

    /**
     * @notice Create a new bounty with escrowed funds
     * @param payout Amount in payment tokens
     * @param deadline Unix timestamp for completion
     * @param descriptionHash IPFS hash of bounty description
     * @return bountyId The ID of the created bounty
     */
    function createBounty(
        uint256 payout,
        uint256 deadline,
        bytes32 descriptionHash
    ) external nonReentrant whenNotPaused returns (uint256 bountyId) {
        if (payout == 0) revert ZeroAmount();
        if (deadline <= block.timestamp) revert InvalidDeadline();
        if (deadline > block.timestamp + MAX_DEADLINE_DURATION) revert InvalidDeadline();

        // Transfer payment token to this contract (escrow)
        paymentToken.safeTransferFrom(msg.sender, address(this), payout);

        bountyId = nextBountyId++;

        bounties[bountyId] = Bounty({
            id: bountyId,
            poster: msg.sender,
            worker: address(0),
            payout: payout,
            deadline: deadline,
            status: BountyStatus.Open,
            createdAt: block.timestamp,
            claimedAt: 0,
            submittedAt: 0,
            descriptionHash: descriptionHash,
            workHash: bytes32(0)
        });

        emit BountyCreated(bountyId, msg.sender, payout, deadline, descriptionHash);
    }

    /**
     * @notice Claim an open bounty
     * @param bountyId ID of bounty to claim
     */
    function claimBounty(uint256 bountyId) external nonReentrant whenNotPaused {
        Bounty storage bounty = bounties[bountyId];
        
        if (bounty.poster == address(0)) revert BountyNotFound();
        if (bounty.status != BountyStatus.Open) revert InvalidStatus();
        if (block.timestamp > bounty.deadline) revert DeadlinePassed();
        if (msg.sender == bounty.poster) revert SelfClaim();

        bounty.worker = msg.sender;
        bounty.status = BountyStatus.Claimed;
        bounty.claimedAt = block.timestamp;

        emit BountyClaimed(bountyId, msg.sender);
    }

    /**
     * @notice Submit work for a claimed bounty
     * @param bountyId ID of bounty
     * @param workHash IPFS hash of submitted work
     */
    function submitWork(uint256 bountyId, bytes32 workHash) external nonReentrant whenNotPaused {
        Bounty storage bounty = bounties[bountyId];

        if (bounty.poster == address(0)) revert BountyNotFound();
        if (bounty.status != BountyStatus.Claimed) revert InvalidStatus();
        if (bounty.worker != msg.sender) revert NotWorker();
        if (block.timestamp > bounty.deadline) revert DeadlinePassed();

        bounty.workHash = workHash;
        bounty.status = BountyStatus.Submitted;
        bounty.submittedAt = block.timestamp;

        emit WorkSubmitted(bountyId, workHash);
    }

    /**
     * @notice Approve submitted work and release payment
     * @param bountyId ID of bounty
     */
    function approveWork(uint256 bountyId) external nonReentrant whenNotPaused {
        Bounty storage bounty = bounties[bountyId];

        if (bounty.poster == address(0)) revert BountyNotFound();
        if (bounty.status != BountyStatus.Submitted) revert InvalidStatus();
        if (bounty.poster != msg.sender) revert NotPoster();

        bounty.status = BountyStatus.Completed;

        // Calculate fees
        uint256 platformFee = (bounty.payout * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
        uint256 workerPayout = bounty.payout - platformFee;

        // Track fees for transparency
        totalFeesCollected += platformFee;

        // Transfer to worker (majority of funds)
        paymentToken.safeTransfer(bounty.worker, workerPayout);
        
        // Transfer fee to platform
        if (platformFee > 0) {
            paymentToken.safeTransfer(feeRecipient, platformFee);
        }

        emit WorkApproved(bountyId, workerPayout, platformFee);
    }

    /**
     * @notice Cancel a bounty and refund (only if Open or abandoned after grace period)
     * @param bountyId ID of bounty
     */
    function cancelBounty(uint256 bountyId) external nonReentrant {
        Bounty storage bounty = bounties[bountyId];

        if (bounty.poster == address(0)) revert BountyNotFound();
        if (bounty.poster != msg.sender) revert NotPoster();
        
        // Can cancel if:
        // 1. Status is Open (not yet claimed)
        // 2. Status is Claimed AND grace period after deadline has passed (abandoned)
        if (bounty.status == BountyStatus.Open) {
            // Direct cancel allowed
        } else if (bounty.status == BountyStatus.Claimed) {
            // Must wait for deadline + grace period
            if (block.timestamp < bounty.deadline + CLAIM_GRACE_PERIOD) {
                revert GracePeriodNotPassed();
            }
        } else {
            revert InvalidStatus();
        }

        bounty.status = BountyStatus.Cancelled;

        // Refund poster
        paymentToken.safeTransfer(bounty.poster, bounty.payout);

        emit BountyCancelled(bountyId);
    }

    /**
     * @notice Mark expired bounty and refund (anyone can call for gas refund)
     * @param bountyId ID of bounty
     */
    function expireBounty(uint256 bountyId) external nonReentrant {
        Bounty storage bounty = bounties[bountyId];

        if (bounty.poster == address(0)) revert BountyNotFound();
        if (bounty.status != BountyStatus.Open) revert InvalidStatus();
        if (block.timestamp <= bounty.deadline) revert DeadlineNotPassed();

        bounty.status = BountyStatus.Expired;

        // Refund poster
        paymentToken.safeTransfer(bounty.poster, bounty.payout);

        emit BountyExpired(bountyId);
    }

    // ============ View Functions ============

    /**
     * @notice Get full bounty details
     * @param bountyId Bounty ID
     */
    function getBounty(uint256 bountyId) external view returns (Bounty memory) {
        return bounties[bountyId];
    }

    /**
     * @notice Check total escrowed balance (for verification)
     */
    function getEscrowedBalance() external view returns (uint256) {
        return paymentToken.balanceOf(address(this));
    }

    // ============ Admin Functions ============

    /**
     * @notice Update fee recipient
     * @param newRecipient New fee recipient address
     */
    function setFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert ZeroAddress();
        
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        
        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    /**
     * @notice Pause contract (emergency only)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ No Rescue Function ============
    // 
    // INTENTIONALLY OMITTED: There is no admin function to withdraw escrowed funds.
    // Funds can ONLY flow through the bounty lifecycle (approve, cancel, expire).
    // This is a security feature, not a bug.
}
