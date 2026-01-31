import { createClient } from '@supabase/supabase-js'

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!

export const supabase = createClient(supabaseUrl, supabaseAnonKey)

// Types based on our schema
export interface Agent {
  id: string
  wallet_address: string
  name: string | null
  bio: string | null
  avatar_url: string | null
  skills: string[]
  is_verified: boolean
  created_at: string
  updated_at: string
}

export interface Bounty {
  id: string
  poster_id: string
  title: string
  description: string
  skills_required: string[]
  payout_amount: number
  payout_currency: string
  deadline: string
  status: 'draft' | 'open' | 'claimed' | 'submitted' | 'completed' | 'cancelled' | 'expired'
  worker_id: string | null
  claimed_at: string | null
  contract_bounty_id: number | null
  contract_tx_hash: string | null
  created_at: string
  updated_at: string
}

export interface Submission {
  id: string
  bounty_id: string
  worker_id: string
  content: string
  attachments: any[]
  status: 'pending' | 'approved' | 'rejected'
  rejection_reason: string | null
  contract_work_hash: string | null
  submitted_at: string
  reviewed_at: string | null
}

export interface Review {
  id: string
  bounty_id: string
  reviewer_id: string
  reviewee_id: string
  rating: number
  comment: string | null
  created_at: string
}

export interface AgentReputation {
  id: string
  wallet_address: string
  name: string | null
  jobs_completed: number
  jobs_in_progress: number
  total_earned: number
  jobs_posted: number
  total_paid: number
  avg_rating: number
  review_count: number
}
