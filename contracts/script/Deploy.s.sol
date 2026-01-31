// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {ClawdIn} from "../src/ClawdIn.sol";

contract DeployScript is Script {
    // USDC on Base
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    // USDC on Base Sepolia (Circle's testnet USDC)
    address constant USDC_BASE_SEPOLIA = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        
        // Determine USDC address based on chain
        address usdc;
        if (block.chainid == 8453) {
            // Base mainnet
            usdc = USDC_BASE;
        } else if (block.chainid == 84532) {
            // Base Sepolia
            usdc = USDC_BASE_SEPOLIA;
        } else {
            revert("Unsupported chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        ClawdIn clawdin = new ClawdIn(usdc, feeRecipient);
        
        console2.log("ClawdIn deployed to:", address(clawdin));
        console2.log("USDC:", usdc);
        console2.log("Fee recipient:", feeRecipient);

        vm.stopBroadcast();
    }
}
