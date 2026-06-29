#!/bin/bash
set -e

SUBMODULES=(
    "tribe-hub"
    "tribe-er-server"
    "tribe-indexer"
    "tribe-sdk"
    "tribe-protocol"
    "homebrew-tap"
    "tribeprotocol.xyz"
    "tribe-tweet-server"
    "tribe-twitter"
    "tribe-twitter-app"
    "tribe-insta"
    "tribe-core-swift"
    "tribeapp.wtf"
)

for sub in "${SUBMODULES[@]}"; do
    if [ -d "$sub" ]; then
        echo "Processing $sub..."
        cd "$sub"
        
        # Check if there are uncommitted changes to README.md
        if git status --porcelain | grep -iq "readme"; then
            readme_file=$(git status --porcelain | grep -i "readme" | awk '{print $2}')
            git add "$readme_file"
            git commit -m "docs: update related repos in README" || true
        fi

        # Push if we are ahead or just committed
        # Actually, let's just forcefully try to push our current HEAD to master
        
        branch=$(git rev-parse --abbrev-ref HEAD)
        if [ "$branch" = "HEAD" ]; then
          branch="master"
        fi

        origin_url=$(git remote get-url origin || true)
        if [ -n "$origin_url" ]; then
            ssh_url=$(echo "$origin_url" | sed -e 's|https://github.com/|git@github.com:|')
            echo "Pushing to $ssh_url"
            git push "$ssh_url" HEAD:$branch || git push "$ssh_url" HEAD:main || true
        fi
        
        cd ..
    fi
done

echo "Processing main repo..."
if git status --porcelain | grep -q "^ M"; then
    git add .
    git commit -m "docs: sync submodule readmes"
    
    branch=$(git rev-parse --abbrev-ref HEAD)
    if [ "$branch" = "HEAD" ]; then
        branch="master"
    fi
    origin_url=$(git remote get-url origin || true)
    if [ -n "$origin_url" ]; then
        ssh_url=$(echo "$origin_url" | sed -e 's|https://github.com/|git@github.com:|')
        echo "Pushing main repo to $ssh_url"
        git push "$ssh_url" HEAD:$branch || git push "$ssh_url" HEAD:main || true
    fi
else
    echo "No changes in main repo"
fi

