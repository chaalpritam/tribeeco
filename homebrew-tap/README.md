# Homebrew Tap for TribeEco

Decentralized Social Protocol on Solana.

## Install

```bash
brew tap chaalpritam/tribe https://github.com/chaalpritam/homebrew-tribe
brew install tribe
```

## Usage

```bash
tribe doctor    # check prerequisites
tribe start     # boot all services
tribe status    # check what's running
tribe logs hub  # tail hub logs
tribe stop      # shut everything down
tribe reset     # wipe data and start fresh
```

## Prerequisites

- **Docker** — Docker Desktop or Colima (`brew install colima`)
- **Node.js** — installed automatically via brew dependency
- **pnpm** — installed automatically via brew dependency

## Publishing this tap

Copy the `Formula/` directory to a new repo named `homebrew-tribe`:

```bash
gh repo create chaalpritam/homebrew-tribe --public
cp -r Formula/ /tmp/homebrew-tribe/
cd /tmp/homebrew-tribe
git init && git add . && git commit -m "Add tribe formula"
git remote add origin git@github.com:chaalpritam/homebrew-tribe.git
git push -u origin main
```
