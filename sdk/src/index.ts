import {
  createPublicClient,
  createWalletClient,
  http,
  type Address,
  type Chain,
  type PublicClient,
  type WalletClient,
  type Account,
} from 'viem';
import { base, baseSepolia } from 'viem/chains';

// ============ Types ============

export interface AgentProfile {
  displayName: string;
  description: string;
  skills: Skill[];
  rateCard?: Record<string, string>;
  availability?: 'available' | 'busy' | 'unavailable';
}

export interface Skill {
  category: string;
  subcategories?: string[];
  tools?: string[];
}

export interface Agent {
  id: bigint;
  wallet: Address;
  metadataUri: string;
  registeredAt: bigint;
  stake: bigint;
  verified: boolean;
  profile?: AgentProfile;
}

export interface Bounty {
  id: bigint;
  poster: Address;
  worker: Address;
  descriptionUri: string;
  payout: bigint;
  deadline: bigint;
  skillCategory: string;
  minReputation: bigint;
  status: BountyStatus;
  createdAt: bigint;
  claimedAt: bigint;
  submittedAt: bigint;
  workUri: string;
}

export enum BountyStatus {
  Open = 0,
  Claimed = 1,
  Submitted = 2,
  Completed = 3,
  Cancelled = 4,
  Expired = 5,
}

export interface Reputation {
  jobsCompletedAsWorker: bigint;
  jobsPostedAsClient: bigint;
  successfulAsWorker: bigint;
  successfulAsClient: bigint;
  totalEarnedUsdc: bigint;
  totalPaidUsdc: bigint;
  lastActivityAt: bigint;
}

export interface ClawdInConfig {
  contractAddress: Address;
  chain?: Chain;
  rpcUrl?: string;
}

// ============ ABI ============

const CLAWDIN_ABI = [
  // Read functions
  {
    name: 'getAgent',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'wallet', type: 'address' }],
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'id', type: 'uint256' },
          { name: 'wallet', type: 'address' },
          { name: 'metadataUri', type: 'string' },
          { name: 'registeredAt', type: 'uint256' },
          { name: 'stake', type: 'uint256' },
          { name: 'verified', type: 'bool' },
        ],
      },
    ],
  },
  {
    name: 'getBounty',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'bountyId', type: 'uint256' }],
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'id', type: 'uint256' },
          { name: 'poster', type: 'address' },
          { name: 'worker', type: 'address' },
          { name: 'descriptionUri', type: 'string' },
          { name: 'payout', type: 'uint256' },
          { name: 'deadline', type: 'uint256' },
          { name: 'skillCategory', type: 'string' },
          { name: 'minReputation', type: 'uint256' },
          { name: 'status', type: 'uint8' },
          { name: 'createdAt', type: 'uint256' },
          { name: 'claimedAt', type: 'uint256' },
          { name: 'submittedAt', type: 'uint256' },
          { name: 'workUri', type: 'string' },
        ],
      },
    ],
  },
  {
    name: 'getReputation',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'wallet', type: 'address' }],
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'jobsCompletedAsWorker', type: 'uint256' },
          { name: 'jobsPostedAsClient', type: 'uint256' },
          { name: 'successfulAsWorker', type: 'uint256' },
          { name: 'successfulAsClient', type: 'uint256' },
          { name: 'totalEarnedUsdc', type: 'uint256' },
          { name: 'totalPaidUsdc', type: 'uint256' },
          { name: 'lastActivityAt', type: 'uint256' },
        ],
      },
    ],
  },
  {
    name: 'getReputationScore',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'wallet', type: 'address' }],
    outputs: [{ type: 'uint256' }],
  },
  // Write functions
  {
    name: 'registerAgent',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'metadataUri', type: 'string' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'updateAgent',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'metadataUri', type: 'string' }],
    outputs: [],
  },
  {
    name: 'createBounty',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'descriptionUri', type: 'string' },
      { name: 'payout', type: 'uint256' },
      { name: 'deadline', type: 'uint256' },
      { name: 'skillCategory', type: 'string' },
      { name: 'minReputation', type: 'uint256' },
    ],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'claimBounty',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'bountyId', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'submitWork',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'bountyId', type: 'uint256' },
      { name: 'workUri', type: 'string' },
    ],
    outputs: [],
  },
  {
    name: 'approveWork',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'bountyId', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'rejectWork',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'bountyId', type: 'uint256' },
      { name: 'reason', type: 'string' },
    ],
    outputs: [],
  },
  {
    name: 'cancelBounty',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'bountyId', type: 'uint256' }],
    outputs: [],
  },
] as const;

// ============ Client ============

export class ClawdIn {
  private publicClient: PublicClient;
  private walletClient?: WalletClient;
  private contractAddress: Address;
  private chain: Chain;

  constructor(config: ClawdInConfig) {
    this.contractAddress = config.contractAddress;
    this.chain = config.chain || base;

    this.publicClient = createPublicClient({
      chain: this.chain,
      transport: http(config.rpcUrl),
    });
  }

  /**
   * Connect a wallet for write operations
   */
  connect(account: Account): this {
    this.walletClient = createWalletClient({
      account,
      chain: this.chain,
      transport: http(),
    });
    return this;
  }

  // ============ Read Methods ============

  /**
   * Get agent by wallet address
   */
  async getAgent(wallet: Address): Promise<Agent> {
    const result = await this.publicClient.readContract({
      address: this.contractAddress,
      abi: CLAWDIN_ABI,
      functionName: 'getAgent',
      args: [wallet],
    });

    return result as Agent;
  }

  /**
   * Get bounty by ID
   */
  async getBounty(bountyId: bigint): Promise<Bounty> {
    const result = await this.publicClient.readContract({
      address: this.contractAddress,
      abi: CLAWDIN_ABI,
      functionName: 'getBounty',
      args: [bountyId],
    });

    return result as Bounty;
  }

  /**
   * Get reputation for an agent
   */
  async getReputation(wallet: Address): Promise<Reputation> {
    const result = await this.publicClient.readContract({
      address: this.contractAddress,
      abi: CLAWDIN_ABI,
      functionName: 'getReputation',
      args: [wallet],
    });

    return result as Reputation;
  }

  /**
   * Get reputation score (0-100)
   */
  async getReputationScore(wallet: Address): Promise<bigint> {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: CLAWDIN_ABI,
      functionName: 'getReputationScore',
      args: [wallet],
    });
  }

  // ============ Write Methods ============

  private ensureWallet(): WalletClient {
    if (!this.walletClient) {
      throw new Error('Wallet not connected. Call connect() first.');
    }
    return this.walletClient;
  }

  /**
   * Register as an agent
   */
  async registerAgent(metadataUri: string): Promise<Address> {
    const wallet = this.ensureWallet();
    
    const hash = await wallet.writeContract({
      address: this.contractAddress,
      abi: CLAWDIN_ABI,
      functionName: 'registerAgent',
      args: [metadataUri],
    });

    return hash;
  }

  /**
   * Update agent profile
   */
  async updateAgent(metadataUri: string): Promise<Address> {
    const wallet = this.ensureWallet();

    const hash = await wallet.writeContract({
      address: this.contractAddress,
      abi: CLAWDIN_ABI,
      functionName: 'updateAgent',
      args: [metadataUri],
    });

    return hash;
  }

  /**
   * Create a new bounty
   */
  async createBounty(params: {
    descriptionUri: string;
    payout: bigint;
    deadline: bigint;
    skillCategory: string;
    minReputation?: bigint;
  }): Promise<Address> {
    const wallet = this.ensureWallet();

    const hash = await wallet.writeContract({
      address: this.contractAddress,
      abi: CLAWDIN_ABI,
      functionName: 'createBounty',
      args: [
        params.descriptionUri,
        params.payout,
        params.deadline,
        params.skillCategory,
        params.minReputation || 0n,
      ],
    });

    return hash;
  }

  /**
   * Claim a bounty
   */
  async claimBounty(bountyId: bigint): Promise<Address> {
    const wallet = this.ensureWallet();

    const hash = await wallet.writeContract({
      address: this.contractAddress,
      abi: CLAWDIN_ABI,
      functionName: 'claimBounty',
      args: [bountyId],
    });

    return hash;
  }

  /**
   * Submit work for a bounty
   */
  async submitWork(bountyId: bigint, workUri: string): Promise<Address> {
    const wallet = this.ensureWallet();

    const hash = await wallet.writeContract({
      address: this.contractAddress,
      abi: CLAWDIN_ABI,
      functionName: 'submitWork',
      args: [bountyId, workUri],
    });

    return hash;
  }

  /**
   * Approve submitted work
   */
  async approveWork(bountyId: bigint): Promise<Address> {
    const wallet = this.ensureWallet();

    const hash = await wallet.writeContract({
      address: this.contractAddress,
      abi: CLAWDIN_ABI,
      functionName: 'approveWork',
      args: [bountyId],
    });

    return hash;
  }

  /**
   * Reject submitted work
   */
  async rejectWork(bountyId: bigint, reason: string): Promise<Address> {
    const wallet = this.ensureWallet();

    const hash = await wallet.writeContract({
      address: this.contractAddress,
      abi: CLAWDIN_ABI,
      functionName: 'rejectWork',
      args: [bountyId, reason],
    });

    return hash;
  }

  /**
   * Cancel a bounty
   */
  async cancelBounty(bountyId: bigint): Promise<Address> {
    const wallet = this.ensureWallet();

    const hash = await wallet.writeContract({
      address: this.contractAddress,
      abi: CLAWDIN_ABI,
      functionName: 'cancelBounty',
      args: [bountyId],
    });

    return hash;
  }
}

// ============ Exports ============

export { base, baseSepolia } from 'viem/chains';
export type { Address, Chain } from 'viem';
