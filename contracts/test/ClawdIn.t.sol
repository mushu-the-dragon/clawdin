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
    address public provider = address(5);

    uint256 constant INITIAL_BALANCE = 10000e6; // 10,000 USDC
    uint256 constant BOUNTY_AMOUNT = 100e6; // 100 USDC

    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy mock USDC
        usdc = new ERC20Mock();
        
        // Deploy ClawdIn
        clawdin = new ClawdIn(address(usdc), feeRecipient);
        
        // Add provider
        clawdin.addProvider(provider);
        
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

    // ============ Registration Tests ============

    function test_RegisterAgent() public {
        vm.prank(poster);
        uint256 agentId = clawdin.registerAgent("ipfs://QmPoster");
        
        assertEq(agentId, 0);
        
        ClawdIn.Agent memory agent = clawdin.getAgent(poster);
        assertEq(agent.wallet, poster);
        assertEq(agent.metadataUri, "ipfs://QmPoster");
        assertFalse(agent.verified);
    }

    function test_RegisterAgent_RevertIfAlreadyRegistered() public {
        vm.startPrank(poster);
        clawdin.registerAgent("ipfs://QmPoster");
        
        vm.expectRevert(ClawdIn.AgentAlreadyRegistered.selector);
        clawdin.registerAgent("ipfs://QmPoster2");
        vm.stopPrank();
    }

    function test_VerifyAgent() public {
        vm.prank(poster);
        clawdin.registerAgent("ipfs://QmPoster");

        vm.prank(provider);
        clawdin.verifyAgent(poster);

        ClawdIn.Agent memory agent = clawdin.getAgent(poster);
        assertTrue(agent.verified);
    }

    // ============ Bounty Tests ============

    function test_CreateBounty() public {
        vm.prank(poster);
        clawdin.registerAgent("ipfs://QmPoster");

        vm.prank(poster);
        uint256 bountyId = clawdin.createBounty(
            "ipfs://QmBounty",
            BOUNTY_AMOUNT,
            block.timestamp + 1 days,
            "code",
            0
        );

        assertEq(bountyId, 0);
        assertEq(usdc.balanceOf(address(clawdin)), BOUNTY_AMOUNT);

        ClawdIn.Bounty memory bounty = clawdin.getBounty(bountyId);
        assertEq(bounty.poster, poster);
        assertEq(bounty.payout, BOUNTY_AMOUNT);
        assertEq(uint256(bounty.status), uint256(ClawdIn.BountyStatus.Open));
    }

    function test_ClaimBounty() public {
        // Setup
        vm.prank(poster);
        clawdin.registerAgent("ipfs://QmPoster");
        
        vm.prank(worker);
        clawdin.registerAgent("ipfs://QmWorker");

        vm.prank(poster);
        uint256 bountyId = clawdin.createBounty(
            "ipfs://QmBounty",
            BOUNTY_AMOUNT,
            block.timestamp + 1 days,
            "code",
            0
        );

        // Claim
        vm.prank(worker);
        clawdin.claimBounty(bountyId);

        ClawdIn.Bounty memory bounty = clawdin.getBounty(bountyId);
        assertEq(bounty.worker, worker);
        assertEq(uint256(bounty.status), uint256(ClawdIn.BountyStatus.Claimed));
    }

    function test_FullFlow() public {
        // Register agents
        vm.prank(poster);
        clawdin.registerAgent("ipfs://QmPoster");
        
        vm.prank(worker);
        clawdin.registerAgent("ipfs://QmWorker");

        // Create bounty
        vm.prank(poster);
        uint256 bountyId = clawdin.createBounty(
            "ipfs://QmBounty",
            BOUNTY_AMOUNT,
            block.timestamp + 1 days,
            "code",
            0
        );

        // Claim bounty
        vm.prank(worker);
        clawdin.claimBounty(bountyId);

        // Submit work
        vm.prank(worker);
        clawdin.submitWork(bountyId, "ipfs://QmWork");

        ClawdIn.Bounty memory bounty = clawdin.getBounty(bountyId);
        assertEq(uint256(bounty.status), uint256(ClawdIn.BountyStatus.Submitted));

        // Approve work
        uint256 workerBalanceBefore = usdc.balanceOf(worker);
        uint256 feeRecipientBalanceBefore = usdc.balanceOf(feeRecipient);

        vm.prank(poster);
        clawdin.approveWork(bountyId);

        // Check final state
        bounty = clawdin.getBounty(bountyId);
        assertEq(uint256(bounty.status), uint256(ClawdIn.BountyStatus.Completed));

        // Check payments (10% fee)
        uint256 expectedFee = BOUNTY_AMOUNT / 10; // 10 USDC
        uint256 expectedWorkerPayout = BOUNTY_AMOUNT - expectedFee; // 90 USDC

        assertEq(usdc.balanceOf(worker), workerBalanceBefore + expectedWorkerPayout);
        assertEq(usdc.balanceOf(feeRecipient), feeRecipientBalanceBefore + expectedFee);

        // Check reputation
        ClawdIn.Reputation memory workerRep = clawdin.getReputation(worker);
        assertEq(workerRep.jobsCompletedAsWorker, 1);
        assertEq(workerRep.successfulAsWorker, 1);
        assertEq(workerRep.totalEarnedUsdc, expectedWorkerPayout);

        ClawdIn.Reputation memory posterRep = clawdin.getReputation(poster);
        assertEq(posterRep.jobsPostedAsClient, 1);
        assertEq(posterRep.successfulAsClient, 1);
        assertEq(posterRep.totalPaidUsdc, BOUNTY_AMOUNT);
    }

    function test_RejectWork() public {
        // Setup and create bounty
        vm.prank(poster);
        clawdin.registerAgent("ipfs://QmPoster");
        
        vm.prank(worker);
        clawdin.registerAgent("ipfs://QmWorker");

        vm.prank(poster);
        uint256 bountyId = clawdin.createBounty(
            "ipfs://QmBounty",
            BOUNTY_AMOUNT,
            block.timestamp + 1 days,
            "code",
            0
        );

        vm.prank(worker);
        clawdin.claimBounty(bountyId);

        vm.prank(worker);
        clawdin.submitWork(bountyId, "ipfs://QmWork");

        // Reject
        vm.prank(poster);
        clawdin.rejectWork(bountyId, "Not what I asked for");

        ClawdIn.Bounty memory bounty = clawdin.getBounty(bountyId);
        assertEq(uint256(bounty.status), uint256(ClawdIn.BountyStatus.Claimed));
        assertEq(bounty.workUri, "");
    }

    function test_CancelOpenBounty() public {
        vm.prank(poster);
        clawdin.registerAgent("ipfs://QmPoster");

        vm.prank(poster);
        uint256 bountyId = clawdin.createBounty(
            "ipfs://QmBounty",
            BOUNTY_AMOUNT,
            block.timestamp + 1 days,
            "code",
            0
        );

        uint256 balanceBefore = usdc.balanceOf(poster);

        vm.prank(poster);
        clawdin.cancelBounty(bountyId);

        assertEq(usdc.balanceOf(poster), balanceBefore + BOUNTY_AMOUNT);
        
        ClawdIn.Bounty memory bounty = clawdin.getBounty(bountyId);
        assertEq(uint256(bounty.status), uint256(ClawdIn.BountyStatus.Cancelled));
    }

    function test_ExpireBounty() public {
        vm.prank(poster);
        clawdin.registerAgent("ipfs://QmPoster");

        vm.prank(poster);
        uint256 bountyId = clawdin.createBounty(
            "ipfs://QmBounty",
            BOUNTY_AMOUNT,
            block.timestamp + 1 days,
            "code",
            0
        );

        // Warp past deadline
        vm.warp(block.timestamp + 2 days);

        uint256 balanceBefore = usdc.balanceOf(poster);

        // Anyone can call expire
        clawdin.expireBounty(bountyId);

        assertEq(usdc.balanceOf(poster), balanceBefore + BOUNTY_AMOUNT);
    }

    // ============ Reputation Tests ============

    function test_ReputationScore() public {
        // Complete 2 successful jobs
        vm.prank(poster);
        clawdin.registerAgent("ipfs://QmPoster");
        
        vm.prank(worker);
        clawdin.registerAgent("ipfs://QmWorker");

        for (uint256 i = 0; i < 2; i++) {
            vm.prank(poster);
            uint256 bountyId = clawdin.createBounty(
                "ipfs://QmBounty",
                BOUNTY_AMOUNT,
                block.timestamp + 1 days,
                "code",
                0
            );

            vm.prank(worker);
            clawdin.claimBounty(bountyId);

            vm.prank(worker);
            clawdin.submitWork(bountyId, "ipfs://QmWork");

            vm.prank(poster);
            clawdin.approveWork(bountyId);
        }

        uint256 score = clawdin.getReputationScore(worker);
        assertEq(score, 100); // 100% success rate
    }

    function test_MinReputationRequirement() public {
        vm.prank(poster);
        clawdin.registerAgent("ipfs://QmPoster");
        
        vm.prank(worker);
        clawdin.registerAgent("ipfs://QmWorker");

        // Create bounty with min reputation
        vm.prank(poster);
        uint256 bountyId = clawdin.createBounty(
            "ipfs://QmBounty",
            BOUNTY_AMOUNT,
            block.timestamp + 1 days,
            "code",
            50 // Require 50% reputation
        );

        // Worker has 0 reputation, should fail
        vm.prank(worker);
        vm.expectRevert(ClawdIn.InsufficientReputation.selector);
        clawdin.claimBounty(bountyId);
    }
}
