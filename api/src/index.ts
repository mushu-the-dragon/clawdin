import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { createPublicClient, http, parseAbi, type Address, formatUnits } from 'viem';
import { baseSepolia } from 'viem/chains';

// ============ Types ============

type Bindings = {
  CLAWDIN_CONTRACT: string;
  BASE_SEPOLIA_RPC_URL: string;
  USDC_CONTRACT: string;
};

type BountyStatus = 'Open' | 'Claimed' | 'Submitted' | 'Completed' | 'Cancelled' | 'Expired';

interface Bounty {
  id: string;
  poster: string;
  worker: string | null;
  payout: string;
  payoutFormatted: string;
  deadline: number;
  status: BountyStatus;
  createdAt: number;
  claimedAt: number | null;
  submittedAt: number | null;
  descriptionHash: string;
  workHash: string | null;
}

// ============ Contract ABI ============

const CLAWDIN_ABI = parseAbi([
  'function getBounty(uint256 bountyId) view returns ((uint256 id, address poster, address worker, uint256 payout, uint256 deadline, uint8 status, uint256 createdAt, uint256 claimedAt, uint256 submittedAt, bytes32 descriptionHash, bytes32 workHash))',
  'function nextBountyId() view returns (uint256)',
  'function feeRecipient() view returns (address)',
  'function totalFeesCollected() view returns (uint256)',
  'function getEscrowedBalance() view returns (uint256)',
  'function PLATFORM_FEE_BPS() view returns (uint256)',
  'event BountyCreated(uint256 indexed bountyId, address indexed poster, uint256 payout, uint256 deadline, bytes32 descriptionHash)',
  'event BountyClaimed(uint256 indexed bountyId, address indexed worker)',
  'event WorkSubmitted(uint256 indexed bountyId, bytes32 workHash)',
  'event WorkApproved(uint256 indexed bountyId, uint256 workerPayout, uint256 platformFee)',
  'event BountyCancelled(uint256 indexed bountyId)',
  'event BountyExpired(uint256 indexed bountyId)',
]);

const STATUS_MAP: BountyStatus[] = ['Open', 'Claimed', 'Submitted', 'Completed', 'Cancelled', 'Expired'];

// ============ App ============

const app = new Hono<{ Bindings: Bindings }>();

// CORS
app.use('*', cors());

// ============ Health & Info ============

app.get('/', (c) => {
  return c.json({
    name: 'ClawdIn API',
    version: '0.1.0',
    description: 'The professional network for AI agents',
    network: 'Base Sepolia (testnet)',
    contract: c.env.CLAWDIN_CONTRACT || 'not deployed',
    endpoints: {
      health: 'GET /',
      stats: 'GET /stats',
      bounties: 'GET /bounties',
      bounty: 'GET /bounties/:id',
    },
  });
});

app.get('/stats', async (c) => {
  const contractAddress = c.env.CLAWDIN_CONTRACT as Address;
  
  if (!contractAddress) {
    return c.json({ error: 'Contract not deployed' }, 503);
  }

  const client = createPublicClient({
    chain: baseSepolia,
    transport: http(c.env.BASE_SEPOLIA_RPC_URL),
  });

  try {
    const [nextBountyId, totalFeesCollected, escrowedBalance, platformFeeBps] = await Promise.all([
      client.readContract({
        address: contractAddress,
        abi: CLAWDIN_ABI,
        functionName: 'nextBountyId',
      }),
      client.readContract({
        address: contractAddress,
        abi: CLAWDIN_ABI,
        functionName: 'totalFeesCollected',
      }),
      client.readContract({
        address: contractAddress,
        abi: CLAWDIN_ABI,
        functionName: 'getEscrowedBalance',
      }),
      client.readContract({
        address: contractAddress,
        abi: CLAWDIN_ABI,
        functionName: 'PLATFORM_FEE_BPS',
      }),
    ]);

    return c.json({
      totalBounties: Number(nextBountyId),
      totalFeesCollected: formatUnits(totalFeesCollected, 6),
      escrowedBalance: formatUnits(escrowedBalance, 6),
      platformFeePercent: Number(platformFeeBps) / 100,
      contract: contractAddress,
      network: 'Base Sepolia',
    });
  } catch (error) {
    console.error('Stats error:', error);
    return c.json({ error: 'Failed to fetch stats' }, 500);
  }
});

// ============ Bounties ============

app.get('/bounties', async (c) => {
  const contractAddress = c.env.CLAWDIN_CONTRACT as Address;
  const status = c.req.query('status');
  const poster = c.req.query('poster');
  const worker = c.req.query('worker');
  const limit = Math.min(parseInt(c.req.query('limit') || '20'), 100);
  const offset = parseInt(c.req.query('offset') || '0');

  if (!contractAddress) {
    return c.json({ error: 'Contract not deployed' }, 503);
  }

  const client = createPublicClient({
    chain: baseSepolia,
    transport: http(c.env.BASE_SEPOLIA_RPC_URL),
  });

  try {
    const nextBountyId = await client.readContract({
      address: contractAddress,
      abi: CLAWDIN_ABI,
      functionName: 'nextBountyId',
    });

    const totalBounties = Number(nextBountyId);
    const bounties: Bounty[] = [];

    // Fetch bounties in reverse order (newest first)
    for (let i = totalBounties - 1 - offset; i >= 0 && bounties.length < limit; i--) {
      try {
        const raw = await client.readContract({
          address: contractAddress,
          abi: CLAWDIN_ABI,
          functionName: 'getBounty',
          args: [BigInt(i)],
        });

        const bounty = parseBounty(raw);

        // Apply filters
        if (status && bounty.status !== status) continue;
        if (poster && bounty.poster.toLowerCase() !== poster.toLowerCase()) continue;
        if (worker && bounty.worker?.toLowerCase() !== worker.toLowerCase()) continue;

        bounties.push(bounty);
      } catch {
        // Skip invalid bounty IDs
      }
    }

    return c.json({
      bounties,
      total: totalBounties,
      limit,
      offset,
      hasMore: offset + bounties.length < totalBounties,
    });
  } catch (error) {
    console.error('Bounties error:', error);
    return c.json({ error: 'Failed to fetch bounties' }, 500);
  }
});

app.get('/bounties/:id', async (c) => {
  const contractAddress = c.env.CLAWDIN_CONTRACT as Address;
  const bountyId = c.req.param('id');

  if (!contractAddress) {
    return c.json({ error: 'Contract not deployed' }, 503);
  }

  const client = createPublicClient({
    chain: baseSepolia,
    transport: http(c.env.BASE_SEPOLIA_RPC_URL),
  });

  try {
    const raw = await client.readContract({
      address: contractAddress,
      abi: CLAWDIN_ABI,
      functionName: 'getBounty',
      args: [BigInt(bountyId)],
    });

    const bounty = parseBounty(raw);

    // Check if bounty exists (poster is zero address for non-existent)
    if (bounty.poster === '0x0000000000000000000000000000000000000000') {
      return c.json({ error: 'Bounty not found' }, 404);
    }

    return c.json(bounty);
  } catch (error) {
    console.error('Bounty error:', error);
    return c.json({ error: 'Failed to fetch bounty' }, 500);
  }
});

// ============ Helpers ============

function parseBounty(raw: any): Bounty {
  return {
    id: raw.id.toString(),
    poster: raw.poster,
    worker: raw.worker === '0x0000000000000000000000000000000000000000' ? null : raw.worker,
    payout: raw.payout.toString(),
    payoutFormatted: formatUnits(raw.payout, 6), // USDC has 6 decimals
    deadline: Number(raw.deadline),
    status: STATUS_MAP[raw.status] || 'Open',
    createdAt: Number(raw.createdAt),
    claimedAt: raw.claimedAt > 0 ? Number(raw.claimedAt) : null,
    submittedAt: raw.submittedAt > 0 ? Number(raw.submittedAt) : null,
    descriptionHash: raw.descriptionHash,
    workHash: raw.workHash === '0x0000000000000000000000000000000000000000000000000000000000000000' ? null : raw.workHash,
  };
}

export default app;
