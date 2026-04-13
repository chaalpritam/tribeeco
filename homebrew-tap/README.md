# Homebrew Tap for TribeEco

Decentralized Social Protocol on Solana.

## Install

```bash
brew tap chaalpritam/tribe-homebrew
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

## Uninstall

```bash
brew uninstall tribe
brew untap chaalpritam/tribe-homebrew
```
