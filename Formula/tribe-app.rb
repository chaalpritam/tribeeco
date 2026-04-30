class TribeApp < Formula
  desc "TribeEco demo frontend (Next.js) — UI for the TribeEco protocol"
  homepage "https://github.com/chaalpritam/tribe-demo-app"
  url "https://github.com/chaalpritam/tribe-demo-app.git",
      branch: "master"
  version "0.1.0"
  license "MIT"

  # Track master via `brew install --HEAD tribe-app` and
  # `brew upgrade --fetch-HEAD tribe-app` for the same self-updating
  # story as the main `tribe` formula — the demo UI moves faster than
  # the protocol so HEAD is the recommended channel.
  head "https://github.com/chaalpritam/tribe-demo-app.git", branch: "master"

  depends_on "node"
  depends_on "pnpm"

  def install
    libexec.install Dir["*"]

    # Wrapper supports two subcommands:
    #   tribe-app                — boot the Next.js dev server on $PORT (default 3002)
    #   tribe-app link <hub-url> — write ~/.tribe/tribe-app.env so subsequent
    #                              runs talk to a remote hub on the LAN
    #
    # The wrapper sources ~/.tribe/tribe-app.env on every run so the env
    # file is the durable source of truth — the in-tree libexec copy gets
    # clobbered by `brew upgrade` but ~/.tribe survives.
    (bin/"tribe-app").write <<~SH
      #!/bin/bash
      set -e
      APP_DIR="#{libexec}"
      ENV_FILE="$HOME/.tribe/tribe-app.env"

      case "${1:-run}" in
        link)
          hub_url="${2:-}"
          if [ -z "$hub_url" ]; then
            echo "Usage: tribe-app link <hub-url>"
            echo "Example: tribe-app link http://chaals-mac-mini.local:4000"
            exit 1
          fi
          hub_url="${hub_url%/}"
          host_part=$(echo "$hub_url" | sed -E 's|^(https?://)([^/:]+)(:[0-9]+)?.*$|\\1\\2|')
          mkdir -p "$HOME/.tribe"
          {
            echo "NEXT_PUBLIC_HUB_URL=$hub_url"
            echo "NEXT_PUBLIC_ER_SERVER_URL=${host_part}:3003"
          } > "$ENV_FILE"
          echo "Wrote $ENV_FILE"
          echo "  NEXT_PUBLIC_HUB_URL=$hub_url"
          echo "  NEXT_PUBLIC_ER_SERVER_URL=${host_part}:3003"
          echo "Restart tribe-app to pick up the new target."
          ;;
        run|"")
          if [ -f "$ENV_FILE" ]; then
            set -a; . "$ENV_FILE"; set +a
          fi
          : "${NEXT_PUBLIC_HUB_URL:=http://localhost:4000}"
          : "${NEXT_PUBLIC_ER_SERVER_URL:=http://localhost:3003}"
          : "${PORT:=3002}"
          export NEXT_PUBLIC_HUB_URL NEXT_PUBLIC_ER_SERVER_URL
          cd "$APP_DIR"
          exec pnpm dev -p "$PORT"
          ;;
        *)
          echo "Usage: tribe-app [run | link <hub-url>]"
          exit 1
          ;;
      esac
    SH
  end

  def post_install
    system "pnpm", "install", "--dir", libexec
  end

  def caveats
    <<~EOS
      tribe-app installed! Run the demo UI with:

        tribe-app                      # http://localhost:3002

      Defaults to a hub at http://localhost:4000. To point this app at a
      hub on another machine on the same Wi-Fi:

        tribe-app link http://chaals-mac-mini.local:4000

      That writes ~/.tribe/tribe-app.env so subsequent runs target it.

      For the full hub + ER stack (the backend this app talks to):
        brew install tribe
    EOS
  end

  test do
    assert_predicate libexec/"package.json", :exist?
  end
end
