import os
import re

standard_table = """## Related Repos

| Repo | Description |
|------|-------------|
| [tribe-protocol](../tribe-protocol) | Solana programs (Anchor) — 12 programs: tid-registry, app-key-registry, username-registry, social-graph w/ ER delegation, hub-registry, tip-registry, crowdfund-registry, task-registry, channel-registry, karma-registry, poll-registry, event-registry |
| [tribe-sdk](../tribe-sdk) | TypeScript SDK — DirectSolana and EphemeralRollup providers; clients for identity, tweets, DMs, profiles, channels, bookmarks, polls, events, tasks, crowdfunds, tips, search |
| [tribe-hub](../tribe-hub) | Decentralized hub — signed-message storage + Solana indexer + gossip peer sync; REST + WebSocket APIs |
| [tribe-er-server](../tribe-er-server) | Ephemeral Rollup sequencer — instant follows, batched L1 settlement every 10s |
| [tribe-twitter-app](../tribe-twitter-app) | Next.js frontend — protocol-first reference client with multi-node failover |
| [tribeapp.wtf](../tribeapp.wtf) | Consumer-facing web app + landing page at tribeapp.wtf — hyperlocal social built entirely on the protocol |
| [tribe-twitter](../tribe-twitter) | Native SwiftUI iOS client (Twitter-shaped) — full read/write against hub + ER, NaCl-box DMs, BLAKE3 + ed25519 signing via Apple CryptoKit |
| [tribe-insta](../tribe-insta) | Native SwiftUI iOS client (Instagram-shaped) — photo grid, stories, reels; same hub + envelope format as tribe-twitter. Scaffolding stage — see `tribe-insta/PLAN.md` |
| [tribe-core-swift](../tribe-core-swift) | Shared Swift package consumed by tribe-twitter + tribe-insta — crypto (BLAKE3, NaCl box, ed25519 signing, BIP39, SolanaHD), backup file format, envelope signer. See `tribe-core-swift/MIGRATION.md` |
| [homebrew-tap](../homebrew-tap) | Homebrew formulas: `brew install tribe` (hub + ER) and `brew install tribe-twitter-app` (demo UI) |
"""

readmes = [
    "./tribe-hub/README.md",
    "./tribe-er-server/README.md",
    "./tribe-indexer/README.md",
    "./tribe-sdk/README.md",
    "./tribe-protocol/README.md",
    "./homebrew-tap/README.md",
    "./tribeprotocol.xyz/README.md",
    "./tribe-cast-server/README.md",
    "./tribe-twitter/README.md",
    "./tribe-twitter-app/README.md",
    "./tribe-insta/README.md",
    "./tribe-core-swift/README.md",
    "./tribeapp.wtf/README.md"
]

for readme_path in readmes:
    if not os.path.exists(readme_path):
        print(f"Skipping {readme_path}, not found.")
        continue
    
    with open(readme_path, "r") as f:
        content = f.read()

    # Regex to find '## Related Repos' and the following table/text up to the next '## ' or end of file
    pattern = re.compile(r"## Related Repos\n(.*?)(?=\n## |\Z)", re.DOTALL)
    
    if pattern.search(content):
        new_content = pattern.sub(standard_table.strip(), content)
        with open(readme_path, "w") as f:
            f.write(new_content)
        print(f"Updated {readme_path}")
    else:
        # If there is no '## Related Repos' section, insert it before '## License'
        # Or at the end if no License section exists
        if "## License" in content:
            new_content = content.replace("## License", standard_table + "\n## License")
            with open(readme_path, "w") as f:
                f.write(new_content)
            print(f"Inserted into {readme_path}")
        else:
            with open(readme_path, "a") as f:
                f.write("\n" + standard_table)
            print(f"Appended to {readme_path}")

