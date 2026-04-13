class Tribe < Formula
  desc "TribeEco - Decentralized Social Protocol on Solana"
  homepage "https://github.com/chaalpritam/TribeEco"
  url "https://github.com/chaalpritam/TribeEco.git",
      tag:      "v0.1.0",
      revision: "HEAD"
  version "0.1.0"
  license "MIT"

  depends_on "node"
  depends_on "pnpm"
  depends_on "docker" => :optional
  depends_on "docker-compose" => :optional

  def install
    # Clone with submodules is handled by brew's git strategy.
    # Install the entire project to libexec so the structure is preserved.
    libexec.install Dir["*"]
    libexec.install ".gitmodules"
    libexec.install ".gitignore"

    # Create a wrapper script that sets TRIBE_HOME and delegates to bin/tribe
    (bin/"tribe").write <<~EOS
      #!/bin/bash
      export TRIBE_HOME="#{libexec}"
      exec "#{libexec}/bin/tribe" "$@"
    EOS
  end

  def post_install
    # Initialize submodules after install
    system "git", "-C", libexec.to_s, "submodule", "update", "--init", "--recursive"
  end

  def caveats
    <<~EOS
      TribeEco has been installed!

      Quick start:
        tribe doctor       # check prerequisites
        tribe start        # boot all services
        tribe status       # see what's running
        tribe stop         # shut it down

      Requirements:
        - Docker must be running (Docker Desktop or Colima)
        - A server wallet is needed at:
          #{libexec}/tribe-er-server/server-wallet.json

      Generate a wallet:
        solana-keygen new -o #{libexec}/tribe-er-server/server-wallet.json --no-bip39-passphrase

      Services:
        Frontend    http://localhost:3002
        Hub API     http://localhost:4000
        ER Server   http://localhost:3003
    EOS
  end

  test do
    assert_match "tribe #{version}", shell_output("#{bin}/tribe version")
  end
end
