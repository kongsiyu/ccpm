#!/bin/bash

# Error Handling and Validation Utility Library
# Provides consistent error handling, validation, and messaging functions

# Set strict mode for bash scripts
# Usage: set_strict_mode
# Enables: exit on error, undefined vars, pipe failures
set_strict_mode() {
    set -euo pipefail
    
    # Set up error trap to show line number on failures
    trap 'echo "❌ Error on line $LINENO in ${BASH_SOURCE[0]}. Exit code: $?" >&2' ERR
}

# Exit with error message
# Usage: error_exit "Error message" [exit_code]
# Default exit code: 1
error_exit() {
    local message="$1"
    local exit_code="${2:-1}"
    
    echo "❌ Error: $message" >&2
    exit "$exit_code"
}

# Print warning message (non-fatal)
# Usage: warning "Warning message"
warning() {
    local message="$1"
    echo "⚠️  Warning: $message" >&2
}

# Print info message
# Usage: info "Info message"
info() {
    local message="$1"
    echo "ℹ️  Info: $message" >&2
}

# Print success message
# Usage: success "Success message"
success() {
    local message="$1"
    echo "✅ $message" >&2
}

# Check if required commands are available
# Usage: require_commands "command1" "command2" ...
# Exits if any command is missing
require_commands() {
    local commands=("$@")
    local missing_commands=()
    
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        error_exit "Missing required commands: ${missing_commands[*]}"
    fi
}

# Validate that an epic exists and is properly formed
# Usage: validate_epic_name "epic_name"
# Returns: 0 on success, exits on failure
validate_epic_name() {
    local epic_name="$1"
    
    if [ -z "$epic_name" ]; then
        error_exit "Epic name is required"
    fi
    
    local epic_file=".claude/epics/$epic_name/epic.md"
    
    if [ ! -f "$epic_file" ]; then
        error_exit "Epic not found: $epic_name. Create it first with: /pm:prd-parse $epic_name"
    fi
    
    # Check if epic has required frontmatter
    if ! grep -q "^name:" "$epic_file"; then
        error_exit "Epic file missing required frontmatter: $epic_file"
    fi
    
    return 0
}

# Validate that a task file exists and is properly formed
# Usage: validate_task_file "path/to/task.md"
# Returns: 0 on success, exits on failure
validate_task_file() {
    local task_file="$1"
    
    if [ -z "$task_file" ]; then
        error_exit "Task file path is required"
    fi
    
    if [ ! -f "$task_file" ]; then
        error_exit "Task file not found: $task_file"
    fi
    
    # Check if task has required frontmatter
    local required_fields=("name" "status")
    for field in "${required_fields[@]}"; do
        if ! grep -q "^$field:" "$task_file"; then
            error_exit "Task file missing required field '$field': $task_file"
        fi
    done
    
    return 0
}

# Validate GitHub CLI authentication
# Usage: validate_github_auth
# Returns: 0 if authenticated, exits if not
validate_github_auth() {
    # Source GitHub library if not already loaded
    if ! type check_github_auth >/dev/null 2>&1; then
        local script_dir="$(dirname "${BASH_SOURCE[0]}")"
        source "$script_dir/github.sh"
    fi
    
    if ! check_github_auth; then
        error_exit "GitHub CLI not authenticated. Run: gh auth login"
    fi
    
    return 0
}

# Validate that we're in a Git repository
# Usage: validate_git_repo
# Returns: 0 if in git repo, exits if not
validate_git_repo() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        error_exit "Not in a Git repository"
    fi
    
    return 0
}

# Validate directory structure exists
# Usage: validate_directory_structure
# Returns: 0 on success, exits on failure
validate_directory_structure() {
    local required_dirs=(
        ".claude"
        ".claude/epics"
        ".claude/context"
        ".claude/commands"
        ".claude/scripts"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            error_exit "Required directory missing: $dir. Run /pm:init to set up the system."
        fi
    done
    
    return 0
}

# Validate that issue number is valid
# Usage: validate_issue_number "123"
# Returns: 0 on success, exits on failure
validate_issue_number() {
    local issue_num="$1"
    
    if [ -z "$issue_num" ]; then
        error_exit "Issue number is required"
    fi
    
    # Check if it's a valid number
    if ! [[ "$issue_num" =~ ^[0-9]+$ ]]; then
        error_exit "Invalid issue number: $issue_num (must be a positive integer)"
    fi
    
    return 0
}

# Find and validate task file for an issue number
# Usage: find_task_file_for_issue "123"
# Returns: Path to task file, or exits if not found
find_task_file_for_issue() {
    local issue_num="$1"
    
    validate_issue_number "$issue_num"
    
    # First check for new naming convention (issue_number.md)
    for epic_dir in .claude/epics/*/; do
        [ -d "$epic_dir" ] || continue
        
        local task_file="$epic_dir/$issue_num.md"
        if [ -f "$task_file" ]; then
            echo "$task_file"
            return 0
        fi
    done
    
    # Fallback to searching by GitHub URL in frontmatter
    for epic_dir in .claude/epics/*/; do
        [ -d "$epic_dir" ] || continue
        
        for task_file in "$epic_dir"/[0-9]*.md; do
            [ -f "$task_file" ] || continue
            
            if grep -q "github:.*issues/$issue_num" "$task_file"; then
                echo "$task_file"
                return 0
            fi
        done
    done
    
    error_exit "No local task found for issue #$issue_num"
}

# Validate file is writable
# Usage: validate_file_writable "path/to/file"
# Returns: 0 if writable, exits if not
validate_file_writable() {
    local file="$1"
    
    if [ -z "$file" ]; then
        error_exit "File path is required"
    fi
    
    if [ -f "$file" ] && [ ! -w "$file" ]; then
        error_exit "File is not writable: $file"
    fi
    
    # Check if parent directory is writable for new files
    local parent_dir
    parent_dir="$(dirname "$file")"
    
    if [ ! -d "$parent_dir" ]; then
        error_exit "Parent directory does not exist: $parent_dir"
    fi
    
    if [ ! -w "$parent_dir" ]; then
        error_exit "Parent directory is not writable: $parent_dir"
    fi
    
    return 0
}

# Validate that a directory exists and is writable
# Usage: validate_directory_writable "path/to/dir"
# Returns: 0 if valid, exits if not
validate_directory_writable() {
    local dir="$1"
    
    if [ -z "$dir" ]; then
        error_exit "Directory path is required"
    fi
    
    if [ ! -d "$dir" ]; then
        error_exit "Directory does not exist: $dir"
    fi
    
    if [ ! -w "$dir" ]; then
        error_exit "Directory is not writable: $dir"
    fi
    
    return 0
}

# Check if running in dry-run mode
# Usage: is_dry_run "$@"
# Returns: 0 if --dry-run flag found, 1 if not
is_dry_run() {
    local args=("$@")
    
    for arg in "${args[@]}"; do
        if [ "$arg" = "--dry-run" ] || [ "$arg" = "-n" ]; then
            return 0
        fi
    done
    
    return 1
}

# Prompt for user confirmation
# Usage: confirm "Proceed with action?" ["default_response"]
# Returns: 0 for yes/y, 1 for no/n
# Default response: "n" if not specified
confirm() {
    local message="$1"
    local default="${2:-n}"
    
    echo -n "$message (y/n) [default: $default]: " >&2
    read -r response
    
    # Use default if no response
    if [ -z "$response" ]; then
        response="$default"
    fi
    
    case "$response" in
        [Yy]|[Yy][Ee][Ss])
            return 0
            ;;
        [Nn]|[Nn][Oo])
            return 1
            ;;
        *)
            warning "Invalid response. Assuming 'no'."
            return 1
            ;;
    esac
}

# Validate JSON structure
# Usage: validate_json "json_string" 
# Returns: 0 if valid JSON, 1 if invalid
validate_json() {
    local json_string="$1"
    
    if [ -z "$json_string" ]; then
        return 1
    fi
    
    echo "$json_string" | jq empty >/dev/null 2>&1
}

# Safe cleanup function for temporary files
# Usage: cleanup_temp_files "pattern1" "pattern2" ...
cleanup_temp_files() {
    local patterns=("$@")
    
    for pattern in "${patterns[@]}"; do
        # Use find for safety instead of rm with globs
        find /tmp -maxdepth 1 -name "$pattern" -type f -mmin +60 -delete 2>/dev/null || true
    done
}

# Set up cleanup trap for script
# Usage: set_cleanup_trap "cleanup_function"
set_cleanup_trap() {
    local cleanup_function="$1"
    
    if [ -z "$cleanup_function" ]; then
        error_exit "Cleanup function name required"
    fi
    
    # Set trap for various exit conditions
    trap "$cleanup_function" EXIT INT TERM
}