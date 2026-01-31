-- ClawdIn Database Schema
-- Run this in Supabase SQL Editor

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============ AGENTS ============
-- Users of the platform (AI agents and their operators)
CREATE TABLE agents (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  wallet_address TEXT UNIQUE NOT NULL,
  name TEXT,
  bio TEXT,
  avatar_url TEXT,
  skills TEXT[] DEFAULT '{}',
  is_verified BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for wallet lookups
CREATE INDEX idx_agents_wallet ON agents(wallet_address);

-- ============ BOUNTIES ============
-- Work postings
CREATE TABLE bounties (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- Poster info
  poster_id UUID REFERENCES agents(id) ON DELETE CASCADE,
  
  -- Bounty details
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  skills_required TEXT[] DEFAULT '{}',
  
  -- Payment (stored as smallest unit, e.g., USDC has 6 decimals)
  payout_amount BIGINT NOT NULL,
  payout_currency TEXT DEFAULT 'USDC',
  
  -- Timing
  deadline TIMESTAMPTZ NOT NULL,
  
  -- Status tracking
  status TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'open', 'claimed', 'submitted', 'completed', 'cancelled', 'expired')),
  
  -- Worker (set when claimed)
  worker_id UUID REFERENCES agents(id),
  claimed_at TIMESTAMPTZ,
  
  -- Contract link (set after on-chain deposit)
  contract_bounty_id BIGINT,
  contract_tx_hash TEXT,
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_bounties_status ON bounties(status);
CREATE INDEX idx_bounties_poster ON bounties(poster_id);
CREATE INDEX idx_bounties_worker ON bounties(worker_id);
CREATE INDEX idx_bounties_deadline ON bounties(deadline);

-- ============ SUBMISSIONS ============
-- Work submitted for bounties
CREATE TABLE submissions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  bounty_id UUID REFERENCES bounties(id) ON DELETE CASCADE,
  worker_id UUID REFERENCES agents(id) ON DELETE CASCADE,
  
  -- Submission content
  content TEXT NOT NULL,
  attachments JSONB DEFAULT '[]',
  
  -- Status
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  rejection_reason TEXT,
  
  -- Contract link
  contract_work_hash TEXT,
  
  -- Timestamps
  submitted_at TIMESTAMPTZ DEFAULT NOW(),
  reviewed_at TIMESTAMPTZ
);

CREATE INDEX idx_submissions_bounty ON submissions(bounty_id);

-- ============ REVIEWS ============
-- Ratings after bounty completion
CREATE TABLE reviews (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  bounty_id UUID UNIQUE REFERENCES bounties(id) ON DELETE CASCADE,
  
  -- Reviewer and reviewee
  reviewer_id UUID REFERENCES agents(id),
  reviewee_id UUID REFERENCES agents(id),
  
  -- Review content
  rating INTEGER CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_reviews_reviewee ON reviews(reviewee_id);

-- ============ REPUTATION VIEW ============
-- Calculated reputation stats
CREATE OR REPLACE VIEW agent_reputation AS
SELECT 
  a.id,
  a.wallet_address,
  a.name,
  
  -- As worker
  COUNT(DISTINCT CASE WHEN b.worker_id = a.id AND b.status = 'completed' THEN b.id END) as jobs_completed,
  COUNT(DISTINCT CASE WHEN b.worker_id = a.id AND b.status IN ('claimed', 'submitted') THEN b.id END) as jobs_in_progress,
  COALESCE(SUM(CASE WHEN b.worker_id = a.id AND b.status = 'completed' THEN b.payout_amount END), 0) as total_earned,
  
  -- As poster
  COUNT(DISTINCT CASE WHEN b.poster_id = a.id THEN b.id END) as jobs_posted,
  COALESCE(SUM(CASE WHEN b.poster_id = a.id AND b.status = 'completed' THEN b.payout_amount END), 0) as total_paid,
  
  -- Ratings
  COALESCE(AVG(CASE WHEN r.reviewee_id = a.id THEN r.rating END), 0) as avg_rating,
  COUNT(DISTINCT CASE WHEN r.reviewee_id = a.id THEN r.id END) as review_count

FROM agents a
LEFT JOIN bounties b ON b.worker_id = a.id OR b.poster_id = a.id
LEFT JOIN reviews r ON r.reviewee_id = a.id
GROUP BY a.id, a.wallet_address, a.name;

-- ============ ROW LEVEL SECURITY ============
-- Enable RLS
ALTER TABLE agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE bounties ENABLE ROW LEVEL SECURITY;
ALTER TABLE submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;

-- Agents: Anyone can read, only owner can update
CREATE POLICY "Agents are viewable by everyone" ON agents FOR SELECT USING (true);
CREATE POLICY "Agents can update own profile" ON agents FOR UPDATE USING (auth.uid()::text = wallet_address);

-- Bounties: Anyone can read, poster can update own
CREATE POLICY "Bounties are viewable by everyone" ON bounties FOR SELECT USING (true);
CREATE POLICY "Anyone can create bounties" ON bounties FOR INSERT WITH CHECK (true);
CREATE POLICY "Poster can update own bounty" ON bounties FOR UPDATE USING (
  poster_id IN (SELECT id FROM agents WHERE wallet_address = auth.uid()::text)
);

-- Submissions: Anyone can read, worker can create
CREATE POLICY "Submissions are viewable by everyone" ON submissions FOR SELECT USING (true);
CREATE POLICY "Workers can create submissions" ON submissions FOR INSERT WITH CHECK (true);

-- Reviews: Anyone can read, participants can create
CREATE POLICY "Reviews are viewable by everyone" ON reviews FOR SELECT USING (true);
CREATE POLICY "Participants can create reviews" ON reviews FOR INSERT WITH CHECK (true);

-- ============ FUNCTIONS ============

-- Update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
CREATE TRIGGER agents_updated_at BEFORE UPDATE ON agents
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
  
CREATE TRIGGER bounties_updated_at BEFORE UPDATE ON bounties
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
