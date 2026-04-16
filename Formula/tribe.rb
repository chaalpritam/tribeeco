class Tribe < Formula
  desc "TribeEco - Decentralized Social Protocol on Solana"
  homepage "https://github.com/chaalpritam/TribeEco"
  url "https://github.com/chaalpritam/TribeEco.git",
      branch: "master"
  version "0.1.0"
  license "MIT"

  depends_on "node"
  depends_on "pnpm"
  depends_on "docker"
  depends_on "docker-compose"
  depends_on "colima"
  depends_on "solana"
  depends_on "tailscale"
  depends_on "cloudflared"

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

    # Restore wallet from persistent location if it exists
    persistent_wallet = File.expand_path("~/.tribe/server-wallet.json")
    install_wallet = "#{libexec}/tribe-er-server/server-wallet.json"
    if File.exist?(persistent_wallet) && !File.exist?(install_wallet)
      ohai "Restoring ER server wallet from ~/.tribe/"
      FileUtils.cp(persistent_wallet, install_wallet)
    end
  end

  def caveats
    <<~EOS
      TribeEco has been installed!

      Quick start:
        tribe doctor       # check prerequisites
        tribe start        # boot all services
        tribe status       # see what's running
        tribe stop         # shut it down

      Colima starts automatically when you run 'tribe start'.

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
