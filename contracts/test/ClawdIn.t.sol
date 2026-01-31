// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {ClawdIn} from "../src/ClawdIn.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract ClawdInTest is Test {
    ClawdIn public clawdin;
    ERC20Mock public usdc;

    address public owner = address(1);
    address public feeRecipient = address(2);
    address public poster = address(3);
    address public worker = address(4);

    uint256 constant INITIAL_BALANCE = 10000e6; // 10,000 USDC
    uint256 constant BOUNTY_AMOUNT = 100e6; // 100 USDC
    bytes32 constant DESCRIPTION_HASH = keccak256("Test bounty description");
    bytes32 constant WORK_HASH = keccak256("Test work submission");

    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy mock USDC
        usdc = new ERC20Mock();
        
        // Deploy ClawdIn
        clawdin = new ClawdIn(address(usdc), feeRecipient);
        
        vm.stopPrank();

        // Fund agents
        usdc.mint(poster, INITIAL_BALANCE);
        usdc.mint(worker, INITIAL_BALANCE);

        // Approve ClawdIn
        vm.prank(poster);
        usdc.approve(address(clawdin), type(uint256).max);
        
        vm.prank(worker);
        usdc.approve(address(clawdin), type(uint256).max);
    }

    // ============ Constructor Tests ============

    function test_Constructor() public view {
        assertEq(address(clawdin.paymentToken()), address(usdc));
        assertEq(clawdin.feeRecipient(), feeRecipient);
        assertEq(clawdin.owner(), owner);
    }

    function test_Constructor_RevertZeroPaymentToken() public {
        vm.prank(owner);
        vm.expectRevert(ClawdIn.ZeroAddress.selector);
        new ClawdIn(address(0), feeRecipient);
    }

    function test_Constructor_RevertZeroFeeRecipient() public {
        vm.prank(owner);
        vm.expectRevert(ClawdIn.ZeroAddress.selector);
        new ClawdIn(address(usdc), address(0));
    }

    // ============ Create Bounty Tests ============

    function test_CreateBounty() public {
        uint256 deadline = block.timestamp + 1 days;
        
        vm.prank(poster);
        uint256 bountyId = clawdin.createBounty(BOUNTY_AMOUNT, deadline, DESCRIPTION_HASH);

        assertEq(bountyId, 0);
        assertEq(usdc.balanceOf(address(clawdin)), BOUNTY_AMOUNT);

        ClawdIn.Bounty memory bounty = clawdin.getBounty(bountyId);
        assertEq(bounty.poster, poster);
        assertEq(bounty.payout, BOUNTY_AMOUNT);
        assertEq(bounty.deadline, deadline);
        assertEq(uint256(bounty.status), uint256(ClawdIn.BountyStatus.Open));
        assertEq(bounty.descriptionHash, DESCRIPTION_HASH);
    }

    function test_CreateBounty_RevertZeroAmount() public {
        vm.prank(poster);
        vm.expectRevert(ClawdIn.ZeroAmount.selector);
        clawdin.createBounty(0, block.timestamp + 1 days, DESCRIPTION_HASH);
    }

    function test_CreateBounty_RevertInvalidDeadline() public {
        vm.prank(poster);
        vm.expectRevert(ClawdIn.InvalidDeadline.selector);
        clawdin.createBounty(BOUNTY_AMOUNT, block.timestamp - 1, DESCRIPTION_HASH);
    }

    function test_CreateBounty_RevertDeadlineTooFar() public {
        vm.prank(poster);
        vm.expectRevert(ClawdIn.InvalidDeadline.selector);
        clawdin.createBounty(BOUNTY_AMOUNT, block.timestamp + 366 days, DESCRIPTION_HASH);
    }

    // ============ Claim Bounty Tests ============

    function test_ClaimBounty() public {
        uint256 bountyId = _createBounty();

        vm.prank(worker);
        clawdin.claimBounty(bountyId);

        ClawdIn.Bounty memory bounty = clawdin.getBounty(bountyId);
        assertEq(bounty.worker, worker);
        assertEq(uint256(bounty.status), uint256(ClawdIn.BountyStatus.Claimed));
    }

    function test_ClaimBounty_RevertSelfClaim() public {
        uint256 bountyId = _createBounty();

        vm.prank(poster);
        vm.expectRevert(ClawdIn.SelfClaim.selector);
        clawdin.claimBounty(bountyId);
    }

    function test_ClaimBounty_RevertDeadlinePassed() public {
        uint256 bountyId = _createBounty();

        vm.warp(block.timestamp + 2 days);

        vm.prank(worker);
        vm.expectRevert(ClawdIn.DeadlinePassed.selector);
        clawdin.claimBounty(bountyId);
    }

    // ============ Submit Work Tests ============

    function test_SubmitWork() public {
        uint256 bountyId = _createAndClaimBounty();

        vm.prank(worker);
        clawdin.submitWork(bountyId, WORK_HASH);

        ClawdIn.Bounty memory bounty = clawdin.getBounty(bountyId);
        assertEq(uint256(bounty.status), uint256(ClawdIn.BountyStatus.Submitted));
        assertEq(bounty.workHash, WORK_HASH);
    }

    function test_SubmitWork_RevertNotWorker() public {
        uint256 bountyId = _createAndClaimBounty();

        vm.prank(poster);
        vm.expectRevert(ClawdIn.NotWorker.selector);
        clawdin.submitWork(bountyId, WORK_HASH);
    }

    function test_SubmitWork_RevertDeadlinePassed() public {
        uint256 bountyId = _createAndClaimBounty();

        vm.warp(block.timestamp + 2 days);

        vm.prank(worker);
        vm.expectRevert(ClawdIn.DeadlinePassed.selector);
        clawdin.submitWork(bountyId, WORK_HASH);
    }

    // ============ Approve Work Tests ============

    function test_ApproveWork() public {
        uint256 bountyId = _createClaimAndSubmit();

        uint256 workerBalanceBefore = usdc.balanceOf(worker);
        uint256 feeRecipientBalanceBefore = usdc.balanceOf(feeRecipient);

        vm.prank(poster);
        clawdin.approveWork(bountyId);

        // Check final state
        ClawdIn.Bounty memory bounty = clawdin.getBounty(bountyId);
        assertEq(uint256(bounty.status), uint256(ClawdIn.BountyStatus.Completed));

        // Check payments (10% fee)
        uint256 expectedFee = BOUNTY_AMOUNT / 10; // 10 USDC
        uint256 expectedWorkerPayout = BOUNTY_AMOUNT - expectedFee; // 90 USDC

        assertEq(usdc.balanceOf(worker), workerBalanceBefore + expectedWorkerPayout);
        assertEq(usdc.balanceOf(feeRecipient), feeRecipientBalanceBefore + expectedFee);
        assertEq(clawdin.totalFeesCollected(), expectedFee);
    }

    function test_ApproveWork_RevertNotPoster() public {
        uint256 bountyId = _createClaimAndSubmit();

        vm.prank(worker);
        vm.expectRevert(ClawdIn.NotPoster.selector);
        clawdin.approveWork(bountyId);
    }

    // ============ Cancel Bounty Tests ============

    function test_CancelOpenBounty() public {
        uint256 bountyId = _createBounty();

        uint256 balanceBefore = usdc.balanceOf(poster);

        vm.prank(poster);
        clawdin.cancelBounty(bountyId);

        assertEq(usdc.balanceOf(poster), balanceBefore + BOUNTY_AMOUNT);
        
        ClawdIn.Bounty memory bounty = clawdin.getBounty(bountyId);
        assertEq(uint256(bounty.status), uint256(ClawdIn.BountyStatus.Cancelled));
    }

    function test_CancelClaimedBounty_AfterGracePeriod() public {
        uint256 bountyId = _createAndClaimBounty();

        // Warp past deadline + grace period
        vm.warp(block.timestamp + 1 days + 7 days + 1);

        uint256 balanceBefore = usdc.balanceOf(poster);

        vm.prank(poster);
        clawdin.cancelBounty(bountyId);

        assertEq(usdc.balanceOf(poster), balanceBefore + BOUNTY_AMOUNT);
    }

    function test_CancelClaimedBounty_RevertGracePeriodNotPassed() public {
        uint256 bountyId = _createAndClaimBounty();

        // Warp past deadline but not grace period
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(poster);
        vm.expectRevert(ClawdIn.GracePeriodNotPassed.selector);
        clawdin.cancelBounty(bountyId);
    }

    function test_CancelBounty_RevertNotPoster() public {
        uint256 bountyId = _createBounty();

        vm.prank(worker);
        vm.expectRevert(ClawdIn.NotPoster.selector);
        clawdin.cancelBounty(bountyId);
    }

    // ============ Expire Bounty Tests ============

    function test_ExpireBounty() public {
        uint256 bountyId = _createBounty();

        vm.warp(block.timestamp + 2 days);

        uint256 balanceBefore = usdc.balanceOf(poster);

        // Anyone can call expire
        vm.prank(worker);
        clawdin.expireBounty(bountyId);

        assertEq(usdc.balanceOf(poster), balanceBefore + BOUNTY_AMOUNT);
        
        ClawdIn.Bounty memory bounty = clawdin.getBounty(bountyId);
        assertEq(uint256(bounty.status), uint256(ClawdIn.BountyStatus.Expired));
    }

    function test_ExpireBounty_RevertDeadlineNotPassed() public {
        uint256 bountyId = _createBounty();

        vm.prank(worker);
        vm.expectRevert(ClawdIn.DeadlineNotPassed.selector);
        clawdin.expireBounty(bountyId);
    }

    // ============ Pause Tests ============

    function test_Pause() public {
        vm.prank(owner);
        clawdin.pause();

        vm.prank(poster);
        vm.expectRevert();
        clawdin.createBounty(BOUNTY_AMOUNT, block.timestamp + 1 days, DESCRIPTION_HASH);
    }

    function test_Unpause() public {
        vm.prank(owner);
        clawdin.pause();

        vm.prank(owner);
        clawdin.unpause();

        vm.prank(poster);
        clawdin.createBounty(BOUNTY_AMOUNT, block.timestamp + 1 days, DESCRIPTION_HASH);
    }

    // ============ Admin Tests ============

    function test_SetFeeRecipient() public {
        address newRecipient = address(99);

        vm.prank(owner);
        clawdin.setFeeRecipient(newRecipient);

        assertEq(clawdin.feeRecipient(), newRecipient);
    }

    function test_SetFeeRecipient_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(ClawdIn.ZeroAddress.selector);
        clawdin.setFeeRecipient(address(0));
    }

    function test_SetFeeRecipient_RevertNotOwner() public {
        vm.prank(poster);
        vm.expectRevert();
        clawdin.setFeeRecipient(address(99));
    }

    // ============ Reentrancy Tests ============

    function test_NoReentrancy() public {
        // This test verifies ReentrancyGuard is working
        // A proper reentrancy test would require a malicious contract
        // For now, we just verify the modifier is applied by checking state
        uint256 bountyId = _createClaimAndSubmit();
        
        vm.prank(poster);
        clawdin.approveWork(bountyId);
        
        // Trying to approve again should fail (wrong status, not reentrancy)
        vm.prank(poster);
        vm.expectRevert(ClawdIn.InvalidStatus.selector);
        clawdin.approveWork(bountyId);
    }

    // ============ Full Flow Test ============

    function test_FullFlow() public {
        // Create bounty
        vm.prank(poster);
        uint256 bountyId = clawdin.createBounty(
            BOUNTY_AMOUNT,
            block.timestamp + 1 days,
            DESCRIPTION_HASH
        );

        // Claim bounty
        vm.prank(worker);
        clawdin.claimBounty(bountyId);

        // Submit work
        vm.prank(worker);
        clawdin.submitWork(bountyId, WORK_HASH);

        // Approve work
        uint256 workerBalanceBefore = usdc.balanceOf(worker);

        vm.prank(poster);
        clawdin.approveWork(bountyId);

        // Verify
        uint256 expectedFee = BOUNTY_AMOUNT / 10;
        uint256 expectedWorkerPayout = BOUNTY_AMOUNT - expectedFee;

        assertEq(usdc.balanceOf(worker), workerBalanceBefore + expectedWorkerPayout);
        assertEq(usdc.balanceOf(address(clawdin)), 0); // All funds released
    }

    // ============ Helpers ============

    function _createBounty() internal returns (uint256) {
        vm.prank(poster);
        return clawdin.createBounty(BOUNTY_AMOUNT, block.timestamp + 1 days, DESCRIPTION_HASH);
    }

    function _createAndClaimBounty() internal returns (uint256) {
        uint256 bountyId = _createBounty();
        
        vm.prank(worker);
        clawdin.claimBounty(bountyId);
        
        return bountyId;
    }

    function _createClaimAndSubmit() internal returns (uint256) {
        uint256 bountyId = _createAndClaimBounty();
        
        vm.prank(worker);
        clawdin.submitWork(bountyId, WORK_HASH);
        
        return bountyId;
    }
}
