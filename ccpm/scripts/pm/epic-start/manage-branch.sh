#!/bin/bash
# Create or switch to epic branch

ARGUMENTS="$1"
if [ -z "$ARGUMENTS" ]; then
  echo "❌ Error: Epic name required"
  exit 1
fi

# Check for uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ You have uncommitted changes. Please commit or stash them before starting an epic."
  exit 1
fi

# If branch doesn't exist, create it
if ! git branch -a | grep -q "epic/$ARGUMENTS"; then
  git checkout main
  git pull origin main
  git checkout -b "epic/$ARGUMENTS"
  git push -u origin "epic/$ARGUMENTS"
  echo "✅ Created branch: epic/$ARGUMENTS"
else
  git checkout "epic/$ARGUMENTS"
  git pull origin "epic/$ARGUMENTS"
  echo "✅ Using existing branch: epic/$ARGUMENTS"
fi