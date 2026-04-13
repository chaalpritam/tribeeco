class Tribe < Formula
  desc "TribeEco - Decentralized Social Protocol on Solana"
  homepage "https://github.com/chaalpritam/TribeEco"
  url "https://github.com/chaalpritam/TribeEco.git",
      branch: "master"
  version "0.1.0"
  license "MIT"

  depends_on "node"
  depends_on "pnpm"

  def install
    libexec.install Dir["*"]
    libexec.install ".gitmodules"
    libexec.install ".gitignore"

    # Wrapper that sets TRIBE_HOME and delegates to the real CLI
    (bin/"tribe").write <<~EOS
      #!/bin/bash
      export TRIBE_HOME="#{libexec}"
      exec "#{libexec}/bin/tribe" "$@"
    EOS
  end

  def post_install
    system "git", "-C", libexec.to_s, "submodule", "update", "--init", "--recursive"
    # Install frontend dependencies
    system "pnpm", "install", "--dir", "#{libexec}/tribe-app"
  end

  def caveats
    <<~EOS
      TribeEco installed! Run 'tribe doctor' to verify your setup.

      Quick start:
        tribe doctor       # verify prerequisites
        tribe start        # boot everything
        tribe status       # check services
        tribe stop         # shut down

      You need Docker running (Docker Desktop or Colima).

      Generate an ER server wallet if you don't have one:
        solana-keygen new -o $(tribe version | grep Home | awk '{print $2}')/tribe-er-server/server-wallet.json --no-bip39-passphrase
    EOS
  end

  test do
    assert_match "tribe #{version}", shell_output("#{bin}/tribe version")
  end
end
