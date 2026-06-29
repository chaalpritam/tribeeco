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
        
        # Check if there are changes to README.md
        if git status --porcelain | grep -iq "readme"; then
            # Get the exact filename
            readme_file=$(git status --porcelain | grep -i "readme" | awk '{print $2}')
            git add "$readme_file"
            git commit -m "docs: update related repos in README"
            
            # Use chaalpritam remote if it exists, otherwise assume origin is setup for ssh
            if git remote -v | grep -q "chaalpritam"; then
                # Get the current branch
                branch=$(git rev-parse --abbrev-ref HEAD)
                if [ "$branch" = "HEAD" ]; then
                  branch="master"
                fi
                git push chaalpritam HEAD:$branch || git push chaalpritam HEAD:main
            else
                git push origin HEAD || true
            fi
        else
            echo "No README changes in $sub"
        fi
        
        cd ..
    fi
done

echo "Processing main repo..."
if git status --porcelain | grep -q "^ M"; then
    git add .
    git commit -m "docs: sync submodule readmes"
    if git remote -v | grep -q "chaalpritam"; then
        branch=$(git rev-parse --abbrev-ref HEAD)
        git push chaalpritam "$branch"
    else
        git push origin HEAD
    fi
else
    echo "No changes in main repo"
fi

