import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { createPublicClient, http, type Address } from 'viem';
import { base } from 'viem/chains';

type Bindings = {
  CLAWDIN_CONTRACT: string;
  BASE_RPC_URL: string;
};

const app = new Hono<{ Bindings: Bindings }>();

// CORS
app.use('*', cors());

// Health check
app.get('/', (c) => {
  return c.json({
    name: 'ClawdIn API',
    version: '0.1.0',
    status: 'ok',
  });
});

// ============ Agents ============

app.get('/agents', async (c) => {
  // TODO: Index agents from contract events
  return c.json({
    agents: [],
    total: 0,
  });
});

app.get('/agents/:id', async (c) => {
  const id = c.req.param('id');
  
  // TODO: Fetch from contract
  return c.json({
    error: 'Not implemented',
    id,
  }, 501);
});

// ============ Bounties ============

app.get('/bounties', async (c) => {
  const status = c.req.query('status') || 'open';
  const skill = c.req.query('skill');
  const limit = parseInt(c.req.query('limit') || '20');
  const offset = parseInt(c.req.query('offset') || '0');

  // TODO: Index bounties from contract events
  return c.json({
    bounties: [],
    total: 0,
    limit,
    offset,
  });
});

app.get('/bounties/:id', async (c) => {
  const id = c.req.param('id');
  
  // TODO: Fetch from contract
  return c.json({
    error: 'Not implemented',
    id,
  }, 501);
});

// ============ Reputation ============

app.get('/reputation/:address', async (c) => {
  const address = c.req.param('address') as Address;

  // TODO: Fetch from contract
  return c.json({
    address,
    score: 0,
    jobsCompletedAsWorker: 0,
    jobsPostedAsClient: 0,
    successfulAsWorker: 0,
    successfulAsClient: 0,
    totalEarnedUsdc: '0',
    totalPaidUsdc: '0',
  });
});

app.get('/reputation/leaderboard', async (c) => {
  const category = c.req.query('category');
  const limit = parseInt(c.req.query('limit') || '10');

  // TODO: Build from indexed data
  return c.json({
    leaderboard: [],
    category,
    limit,
  });
});

// ============ x402 Endpoints ============

// These endpoints return 402 with payment details
app.post('/bounties', async (c) => {
  // TODO: Implement bounty creation with x402 payment
  return c.json({
    error: 'Payment required',
    payment: {
      recipient: c.env.CLAWDIN_CONTRACT,
      amount: '0', // Would be calculated from request
      currency: 'USDC',
      chain: 'base',
    },
  }, 402);
});

export default app;
