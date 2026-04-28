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
    # Brew's GitDownloadStrategy stages a working tree but doesn't auto-init
    # submodules — every submodule directory in the stage is empty. Doing
    # `git submodule update` here, in the staging dir (which is itself a git
    # checkout), means `libexec.install Dir["*"]` below copies populated
    # submodule trees instead of empty placeholders.
    #
    # GIT_TERMINAL_PROMPT=0 prevents the install from hanging if a submodule
    # remote is private or unreachable, and we init each submodule
    # individually so one failure warns + continues instead of aborting.
    ENV["GIT_TERMINAL_PROMPT"] = "0"
    submodules = `git config -f .gitmodules --get-regexp '^submodule\\..*\\.path$' 2>/dev/null`
                   .lines.map { |l| l.split(/\s+/, 2)[1].to_s.strip }.reject(&:empty?)
    submodules.each do |path|
      unless quiet_system "git", "submodule", "update", "--init", "--recursive", "--depth", "1", path
        opoo "Skipping submodule '#{path}' (clone failed — likely private or unavailable)."
      end
    end

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
    # Install frontend dependencies (skip if submodule was unavailable)
    if File.exist?("#{libexec}/tribe-app/package.json")
      system "pnpm", "install", "--dir", "#{libexec}/tribe-app"
    else
      opoo "Skipping pnpm install — tribe-app submodule wasn't cloned."
    end

    # Restore wallet from persistent location if it exists
    persistent_wallet = File.expand_path("~/.tribe/server-wallet.json")
    install_wallet = "#{libexec}/tribe-er-server/server-wallet.json"
    er_dir = File.dirname(install_wallet)
    if File.exist?(persistent_wallet) && File.directory?(er_dir) && !File.exist?(install_wallet)
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
