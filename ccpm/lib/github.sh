#!/bin/bash

# GitHub CLI Utility Library
# Provides common functions for GitHub operations using gh CLI

# Check if GitHub CLI is authenticated
# Usage: check_github_auth
# Returns: 0 if authenticated, 1 if not
check_github_auth() {
    gh auth status >/dev/null 2>&1
}

# Validate GitHub authentication and exit on failure
# Usage: require_github_auth
# Returns: 0 if authenticated, exits with error if not
require_github_auth() {
    if ! check_github_auth; then
        echo "❌ GitHub CLI not authenticated. Run: gh auth login" >&2
        exit 1
    fi
}

# Get current repository name in owner/repo format
# Usage: get_current_repo
# Returns: Repository name (e.g., "owner/repo") or empty if not in a git repo
get_current_repo() {
    # Try to get from gh CLI first
    local repo
    repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
    
    if [ -n "$repo" ]; then
        echo "$repo"
        return 0
    fi
    
    # Fallback to parsing git remote
    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null)
    
    if [ -n "$remote_url" ]; then
        # Parse different URL formats
        local parsed_repo="$remote_url"
        
        # Handle https://github.com/owner/repo.git
        parsed_repo=$(echo "$parsed_repo" | sed -E 's#^https://github\.com/##')
        
        # Handle git@github.com:owner/repo.git
        parsed_repo=$(echo "$parsed_repo" | sed -E 's#^git@github\.com:##')
        
        # Handle ssh:// variants
        parsed_repo=$(echo "$parsed_repo" | sed -E 's#^ssh://git@github\.com/##')
        parsed_repo=$(echo "$parsed_repo" | sed -E 's#^ssh://github\.com/##')
        
        # Remove .git suffix
        parsed_repo=$(echo "$parsed_repo" | sed 's#\.git$##')
        
        echo "$parsed_repo"
        return 0
    fi
    
    echo ""
    return 1
}

# Create a GitHub issue
# Usage: create_github_issue "title" "body" ["label1,label2"] ["assignee"]
# Returns: Issue number on success, empty on failure
create_github_issue() {
    local title="$1"
    local body="$2"
    local labels="$3"
    local assignee="$4"
    local repo="${5:-}"
    
    if [ -z "$title" ]; then
        echo "Error: Issue title required" >&2
        return 1
    fi
    
    # Build gh issue create command
    local gh_cmd="gh issue create --title \"$title\""
    
    if [ -n "$body" ]; then
        # Create temp file for body
        local body_file="/tmp/gh_issue_body_$$"
        echo "$body" > "$body_file"
        gh_cmd="$gh_cmd --body-file \"$body_file\""
    fi
    
    if [ -n "$labels" ]; then
        gh_cmd="$gh_cmd --label \"$labels\""
    fi
    
    if [ -n "$assignee" ]; then
        gh_cmd="$gh_cmd --assignee \"$assignee\""
    fi
    
    if [ -n "$repo" ]; then
        gh_cmd="$gh_cmd --repo \"$repo\""
    fi
    
    # Execute command and extract issue number
    local result
    result=$(eval "$gh_cmd" 2>/dev/null)
    
    # Clean up temp file
    [ -n "$body" ] && rm -f "$body_file" 2>/dev/null
    
    if [ $? -eq 0 ] && [ -n "$result" ]; then
        # Extract issue number from URL
        echo "$result" | grep -oE '[0-9]+$'
        return 0
    else
        echo ""
        return 1
    fi
}

# Update a GitHub issue
# Usage: update_github_issue "issue_number" ["title"] ["body"] ["labels"]
# Returns: 0 on success, 1 on failure
update_github_issue() {
    local issue_number="$1"
    local title="$2"
    local body="$3"
    local labels="$4"
    local repo="${5:-}"
    
    if [ -z "$issue_number" ]; then
        echo "Error: Issue number required" >&2
        return 1
    fi
    
    # Build gh issue edit command
    local gh_cmd="gh issue edit \"$issue_number\""
    
    if [ -n "$title" ]; then
        gh_cmd="$gh_cmd --title \"$title\""
    fi
    
    if [ -n "$body" ]; then
        # Create temp file for body
        local body_file="/tmp/gh_issue_body_$$"
        echo "$body" > "$body_file"
        gh_cmd="$gh_cmd --body-file \"$body_file\""
    fi
    
    if [ -n "$labels" ]; then
        gh_cmd="$gh_cmd --add-label \"$labels\""
    fi
    
    if [ -n "$repo" ]; then
        gh_cmd="$gh_cmd --repo \"$repo\""
    fi
    
    # Execute command
    eval "$gh_cmd" >/dev/null 2>&1
    local result=$?
    
    # Clean up temp file
    [ -n "$body" ] && rm -f "$body_file" 2>/dev/null
    
    return $result
}

# Get GitHub issue data as JSON
# Usage: get_github_issue "issue_number" ["repo"]
# Returns: JSON data or empty on failure
get_github_issue() {
    local issue_number="$1"
    local repo="${2:-}"
    
    if [ -z "$issue_number" ]; then
        echo "Error: Issue number required" >&2
        return 1
    fi
    
    local gh_cmd="gh issue view \"$issue_number\" --json number,title,body,state,labels,updatedAt,createdAt"
    
    if [ -n "$repo" ]; then
        gh_cmd="$gh_cmd --repo \"$repo\""
    fi
    
    eval "$gh_cmd" 2>/dev/null
}

# Post a comment to a GitHub issue
# Usage: post_github_comment "issue_number" "comment_body" ["repo"]
# Returns: 0 on success, 1 on failure
post_github_comment() {
    local issue_number="$1"
    local comment_body="$2"
    local repo="${3:-}"
    
    if [ -z "$issue_number" ] || [ -z "$comment_body" ]; then
        echo "Error: Issue number and comment body required" >&2
        return 1
    fi
    
    # Create temp file for comment body
    local body_file="/tmp/gh_comment_body_$$"
    echo "$comment_body" > "$body_file"
    
    local gh_cmd="gh issue comment \"$issue_number\" --body-file \"$body_file\""
    
    if [ -n "$repo" ]; then
        gh_cmd="$gh_cmd --repo \"$repo\""
    fi
    
    eval "$gh_cmd" >/dev/null 2>&1
    local result=$?
    
    # Clean up temp file
    rm -f "$body_file" 2>/dev/null
    
    return $result
}

# Close a GitHub issue with optional comment
# Usage: close_github_issue "issue_number" ["closing_comment"] ["repo"]
# Returns: 0 on success, 1 on failure
close_github_issue() {
    local issue_number="$1"
    local closing_comment="$2"
    local repo="${3:-}"
    
    if [ -z "$issue_number" ]; then
        echo "Error: Issue number required" >&2
        return 1
    fi
    
    # Post comment if provided
    if [ -n "$closing_comment" ]; then
        post_github_comment "$issue_number" "$closing_comment" "$repo"
    fi
    
    # Close the issue
    local gh_cmd="gh issue close \"$issue_number\""
    
    if [ -n "$repo" ]; then
        gh_cmd="$gh_cmd --repo \"$repo\""
    fi
    
    eval "$gh_cmd" >/dev/null 2>&1
}

# Reopen a GitHub issue with optional comment
# Usage: reopen_github_issue "issue_number" ["reopening_comment"] ["repo"]
# Returns: 0 on success, 1 on failure
reopen_github_issue() {
    local issue_number="$1"
    local reopening_comment="$2"
    local repo="${3:-}"
    
    if [ -z "$issue_number" ]; then
        echo "Error: Issue number required" >&2
        return 1
    fi
    
    # Reopen the issue
    local gh_cmd="gh issue reopen \"$issue_number\""
    
    if [ -n "$repo" ]; then
        gh_cmd="$gh_cmd --repo \"$repo\""
    fi
    
    eval "$gh_cmd" >/dev/null 2>&1
    local result=$?
    
    # Post comment if provided
    if [ -n "$reopening_comment" ] && [ $result -eq 0 ]; then
        post_github_comment "$issue_number" "$reopening_comment" "$repo"
    fi
    
    return $result
}

# List GitHub issues with specific criteria
# Usage: list_github_issues ["state"] ["labels"] ["limit"] ["repo"]
# Returns: JSON array of issues
list_github_issues() {
    local state="${1:-all}"
    local labels="$2"
    local limit="${3:-100}"
    local repo="$4"
    
    local gh_cmd="gh issue list --state \"$state\" --limit $limit --json number,title,state,labels,updatedAt,createdAt"
    
    if [ -n "$labels" ]; then
        gh_cmd="$gh_cmd --label \"$labels\""
    fi
    
    if [ -n "$repo" ]; then
        gh_cmd="$gh_cmd --repo \"$repo\""
    fi
    
    eval "$gh_cmd" 2>/dev/null
}

# Extract issue number from GitHub URL
# Usage: extract_issue_number_from_url "https://github.com/owner/repo/issues/123"
# Returns: Issue number or empty if not found
extract_issue_number_from_url() {
    local url="$1"
    
    if [ -z "$url" ]; then
        echo ""
        return 1
    fi
    
    # Extract number from various GitHub URL formats
    echo "$url" | grep -oE '[0-9]+$'
}

# Check if a GitHub issue exists
# Usage: github_issue_exists "issue_number" ["repo"]
# Returns: 0 if exists, 1 if not
github_issue_exists() {
    local issue_number="$1"
    local repo="${2:-}"
    
    if [ -z "$issue_number" ]; then
        return 1
    fi
    
    local gh_cmd="gh issue view \"$issue_number\" --json number"
    
    if [ -n "$repo" ]; then
        gh_cmd="$gh_cmd --repo \"$repo\""
    fi
    
    eval "$gh_cmd" >/dev/null 2>&1
}

# Get all issues with a specific label
# Usage: get_issues_by_label "label_name" ["state"] ["repo"]
# Returns: JSON array of issues
get_issues_by_label() {
    local label="$1"
    local state="${2:-all}"
    local repo="$3"
    
    if [ -z "$label" ]; then
        echo "[]"
        return 1
    fi
    
    list_github_issues "$state" "$label" 1000 "$repo"
}

# Add labels to a GitHub issue
# Usage: add_github_labels "issue_number" "label1,label2" ["repo"]
# Returns: 0 on success, 1 on failure
add_github_labels() {
    local issue_number="$1"
    local labels="$2"
    local repo="${3:-}"
    
    if [ -z "$issue_number" ] || [ -z "$labels" ]; then
        echo "Error: Issue number and labels required" >&2
        return 1
    fi
    
    local gh_cmd="gh issue edit \"$issue_number\" --add-label \"$labels\""
    
    if [ -n "$repo" ]; then
        gh_cmd="$gh_cmd --repo \"$repo\""
    fi
    
    eval "$gh_cmd" >/dev/null 2>&1
}

# Remove labels from a GitHub issue
# Usage: remove_github_labels "issue_number" "label1,label2" ["repo"]
# Returns: 0 on success, 1 on failure  
remove_github_labels() {
    local issue_number="$1"
    local labels="$2"
    local repo="${3:-}"
    
    if [ -z "$issue_number" ] || [ -z "$labels" ]; then
        echo "Error: Issue number and labels required" >&2
        return 1
    fi
    
    local gh_cmd="gh issue edit \"$issue_number\" --remove-label \"$labels\""
    
    if [ -n "$repo" ]; then
        gh_cmd="$gh_cmd --repo \"$repo\""
    fi
    
    eval "$gh_cmd" >/dev/null 2>&1
}