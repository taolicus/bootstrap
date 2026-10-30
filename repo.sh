#!/bin/sh
set -e

REPO_NAME="${1:-$(basename "$PWD")}"

# Initialise git if needed
if [ ! -d .git ]; then
    git init
fi

# Create public GitHub repository
gh repo create "$REPO_NAME" --public --source=. --remote=origin

# Add and commit files
git add .
git commit -m "init"

# Push
git push -u origin HEAD
