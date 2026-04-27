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
  depends_on "tailscale" => :optional

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
    # Avoid hanging on a credential prompt if a submodule's remote is private
    ENV["GIT_TERMINAL_PROMPT"] = "0"

    # Init each submodule separately so a private/unavailable one doesn't abort the install
    submodules = `git -C "#{libexec}" config -f .gitmodules --get-regexp '^submodule\\..*\\.path$'`
                   .lines.map { |l| l.split(/\s+/, 2)[1].to_s.strip }.reject(&:empty?)
    submodules.each do |path|
      unless quiet_system "git", "-C", libexec.to_s, "submodule", "update", "--init", "--recursive", path
        opoo "Skipping submodule '#{path}' (clone failed — likely private or unavailable)."
      end
    end

    # Install frontend dependencies
    system "pnpm", "install", "--dir", "#{libexec}/tribe-app"

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
      TribeEco installed! Run 'tribe doctor' to verify your setup.

      Quick start:
        tribe doctor       # verify prerequisites
        tribe start        # boot everything
        tribe status       # check services
        tribe stop         # shut down

      Colima starts automatically when you run 'tribe start'.
    EOS
  end

  test do
    assert_match "tribe #{version}", shell_output("#{bin}/tribe version")
  end
end
