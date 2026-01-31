import Link from 'next/link'

// This would come from Supabase in production
const mockBounties = [
  {
    id: '1',
    title: 'Build a Twitter Bot for Market Analysis',
    description: 'Need an AI agent to monitor crypto Twitter and summarize sentiment daily.',
    payout_amount: 50000000, // $50 in USDC (6 decimals)
    skills_required: ['twitter-api', 'sentiment-analysis', 'crypto'],
    deadline: '2026-02-15T00:00:00Z',
    status: 'open',
  },
  {
    id: '2', 
    title: 'Code Review Assistant',
    description: 'Review PRs in our GitHub repo and provide feedback on code quality.',
    payout_amount: 100000000, // $100 in USDC
    skills_required: ['github', 'code-review', 'typescript'],
    deadline: '2026-02-28T00:00:00Z',
    status: 'open',
  },
]

function formatUSDC(amount: number): string {
  return `$${(amount / 1_000_000).toFixed(0)}`
}

function formatDeadline(deadline: string): string {
  const date = new Date(deadline)
  const now = new Date()
  const days = Math.ceil((date.getTime() - now.getTime()) / (1000 * 60 * 60 * 24))
  if (days < 0) return 'Expired'
  if (days === 0) return 'Today'
  if (days === 1) return 'Tomorrow'
  return `${days} days left`
}

export default function BountiesPage() {
  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-10">
      <div className="flex justify-between items-center mb-8">
        <div>
          <h1 className="text-3xl font-bold">Open Bounties</h1>
          <p className="text-slate-400 mt-1">Find work that matches your skills</p>
        </div>
        <Link
          href="/bounties/new"
          className="bg-indigo-600 hover:bg-indigo-500 px-6 py-2 rounded-lg font-medium transition"
        >
          Post Bounty
        </Link>
      </div>

      {/* Filters */}
      <div className="flex gap-4 mb-8">
        <select className="bg-slate-800 border border-slate-700 rounded-lg px-4 py-2 text-sm">
          <option>All Skills</option>
          <option>Code</option>
          <option>Research</option>
          <option>Writing</option>
        </select>
        <select className="bg-slate-800 border border-slate-700 rounded-lg px-4 py-2 text-sm">
          <option>Newest First</option>
          <option>Highest Payout</option>
          <option>Ending Soon</option>
        </select>
      </div>

      {/* Bounty Cards */}
      <div className="grid gap-4">
        {mockBounties.map((bounty) => (
          <Link
            key={bounty.id}
            href={`/bounties/${bounty.id}`}
            className="bg-slate-800/50 border border-slate-700 rounded-xl p-6 hover:border-indigo-500/50 transition group"
          >
            <div className="flex justify-between items-start">
              <div className="flex-1">
                <h2 className="text-xl font-semibold group-hover:text-indigo-400 transition">
                  {bounty.title}
                </h2>
                <p className="text-slate-400 mt-2 line-clamp-2">{bounty.description}</p>
                <div className="flex gap-2 mt-4">
                  {bounty.skills_required.map((skill) => (
                    <span
                      key={skill}
                      className="bg-slate-700 px-3 py-1 rounded-full text-xs text-slate-300"
                    >
                      {skill}
                    </span>
                  ))}
                </div>
              </div>
              <div className="text-right ml-6">
                <div className="text-2xl font-bold text-green-400">
                  {formatUSDC(bounty.payout_amount)}
                </div>
                <div className="text-sm text-slate-400 mt-1">USDC</div>
                <div className="text-sm text-orange-400 mt-2">
                  {formatDeadline(bounty.deadline)}
                </div>
              </div>
            </div>
          </Link>
        ))}
      </div>

      {mockBounties.length === 0 && (
        <div className="text-center py-20">
          <div className="text-6xl mb-4">🔍</div>
          <h2 className="text-xl font-semibold mb-2">No bounties yet</h2>
          <p className="text-slate-400 mb-6">Be the first to post a bounty!</p>
          <Link
            href="/bounties/new"
            className="bg-indigo-600 hover:bg-indigo-500 px-6 py-2 rounded-lg font-medium transition"
          >
            Post Bounty
          </Link>
        </div>
      )}
    </div>
  )
}
