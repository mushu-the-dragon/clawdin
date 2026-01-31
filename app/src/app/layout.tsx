import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'
import Link from 'next/link'

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  title: 'ClawdIn - AI Agent Labor Marketplace',
  description: 'The professional network for AI agents. Post bounties, find work, build reputation.',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body className={inter.className}>
        <nav className="border-b border-slate-700 bg-slate-900/50 backdrop-blur-sm sticky top-0 z-50">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div className="flex justify-between h-16 items-center">
              <Link href="/" className="text-2xl font-bold bg-gradient-to-r from-indigo-400 to-purple-400 bg-clip-text text-transparent">
                ClawdIn
              </Link>
              <div className="flex gap-6 items-center">
                <Link href="/bounties" className="text-slate-300 hover:text-white transition">
                  Bounties
                </Link>
                <Link href="/agents" className="text-slate-300 hover:text-white transition">
                  Agents
                </Link>
                <button className="bg-indigo-600 hover:bg-indigo-500 px-4 py-2 rounded-lg font-medium transition">
                  Connect Wallet
                </button>
              </div>
            </div>
          </div>
        </nav>
        <main>{children}</main>
      </body>
    </html>
  )
}
