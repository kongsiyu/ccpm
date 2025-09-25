#!/bin/bash

# Issue Closing Script
# Marks an issue as complete and closes it on GitHub

# Source utility libraries
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

source "$LIB_DIR/error.sh"
source "$LIB_DIR/frontmatter.sh"
source "$LIB_DIR/datetime.sh"
source "$LIB_DIR/discovery.sh"
source "$LIB_DIR/github.sh"

set_strict_mode

# Main function to close an issue
# Usage: close_issue "issue_number" ["completion_notes"]
close_issue() {
    local issue_number="$1"
    local completion_notes="$2"
    
    if [ -z "$issue_number" ]; then
        error_exit "Issue number is required"
    fi
    
    validate_issue_number "$issue_number"
    validate_github_auth
    
    info "Closing issue #$issue_number..."
    
    # Step 1: Find local task file
    local task_file
    task_file=$(find_task_file_for_issue "$issue_number")
    
    if [ -z "$task_file" ] || [ ! -f "$task_file" ]; then
        error_exit "No local task found for issue #$issue_number"
    fi
    
    local epic_name
    epic_name=$(find_epic_containing_issue "$issue_number")
    
    if [ -z "$epic_name" ]; then
        error_exit "Could not determine epic for issue #$issue_number"
    fi
    
    info "Found task file: $task_file (epic: $epic_name)"
    
    # Step 2: Update local status
    update_local_task_status "$task_file" "$completion_notes"
    
    # Step 3: Update progress file if it exists
    update_progress_file "$epic_name" "$issue_number" "$completion_notes"
    
    # Step 4: Close on GitHub
    close_github_issue_with_comment "$issue_number" "$completion_notes"
    
    # Step 5: Update epic task list on GitHub
    update_epic_task_list "$epic_name" "$issue_number"
    
    # Step 6: Update epic progress
    update_epic_progress "$epic_name"
    
    # Final output
    local epic_progress
    epic_progress=$(get_epic_progress "$epic_name")
    local total_tasks
    total_tasks=$(get_epic_task_count "$epic_name")
    local closed_tasks
    closed_tasks=$(get_epic_task_count_by_status "$epic_name" "closed")
    
    success "Closed issue #$issue_number"
    echo "  Local: Task marked complete"
    echo "  GitHub: Issue closed & epic updated"
    echo "  Epic progress: ${epic_progress}% (${closed_tasks}/${total_tasks} tasks complete)"
    echo ""
    echo "Next: Run /pm:next for next priority task"
}

# Update local task status
update_local_task_status() {
    local task_file="$1"
    local completion_notes="$2"
    
    info "Updating local task status..."
    
    local current_timestamp
    current_timestamp=$(get_current_iso_timestamp)
    
    # Update task frontmatter
    update_frontmatter_bulk "$task_file" \
        "status:closed" \
        "updated:$current_timestamp"
    
    # Add completion notes to task if provided
    if [ -n "$completion_notes" ]; then
        # Append completion note to the task file
        {
            echo ""
            echo "## Completion Notes"
            echo ""
            echo "$completion_notes"
            echo ""
            echo "Completed: $(format_timestamp_display "$current_timestamp")"
        } >> "$task_file"
    fi
    
    success "Local task status updated"
}

# Update progress file
update_progress_file() {
    local epic_name="$1"
    local issue_number="$2"
    local completion_notes="$3"
    
    local progress_file=".claude/epics/$epic_name/updates/$issue_number/progress.md"
    
    if [ -f "$progress_file" ]; then
        info "Updating progress file..."
        
        local current_timestamp
        current_timestamp=$(get_current_iso_timestamp)
        
        # Update progress frontmatter
        update_frontmatter_bulk "$progress_file" \
            "completion:100" \
            "last_sync:$current_timestamp"
        
        # Add completion note
        {
            echo ""
            echo "## Final Update"
            echo ""
            echo "✅ Task completed"
            echo ""
            if [ -n "$completion_notes" ]; then
                echo "$completion_notes"
                echo ""
            fi
            echo "Completed at: $(format_timestamp_display "$current_timestamp")"
        } >> "$progress_file"
        
        success "Progress file updated"
    fi
}

# Close GitHub issue with comment
close_github_issue_with_comment() {
    local issue_number="$1"
    local completion_notes="$2"
    
    info "Closing GitHub issue..."
    
    local current_timestamp
    current_timestamp=$(get_current_iso_timestamp)
    
    # Prepare closing comment
    local closing_comment="✅ Task completed"
    
    if [ -n "$completion_notes" ]; then
        closing_comment="$closing_comment

$completion_notes"
    fi
    
    closing_comment="$closing_comment

---
Closed at: $(format_timestamp_display "$current_timestamp")"
    
    # Close issue with comment
    if close_github_issue "$issue_number" "$closing_comment"; then
        success "GitHub issue closed"
    else
        error_exit "Failed to close GitHub issue #$issue_number"
    fi
}

# Update epic task list on GitHub
update_epic_task_list() {
    local epic_name="$1"
    local issue_number="$2"
    
    info "Updating epic task list on GitHub..."
    
    # Get epic issue number
    local epic_file=".claude/epics/$epic_name/epic.md"
    local epic_github_url
    epic_github_url=$(get_frontmatter_field "$epic_file" "github")
    
    if [ -z "$epic_github_url" ]; then
        warning "Epic has no GitHub URL - cannot update task list"
        return 0
    fi
    
    local epic_issue_number
    epic_issue_number=$(extract_issue_number_from_url "$epic_github_url")
    
    if [ -z "$epic_issue_number" ]; then
        warning "Could not extract epic issue number from URL: $epic_github_url"
        return 0
    fi
    
    # Get current epic body
    local epic_data
    epic_data=$(get_github_issue "$epic_issue_number")
    
    if [ -z "$epic_data" ]; then
        warning "Could not fetch epic issue #$epic_issue_number"
        return 0
    fi
    
    # Extract current body
    local current_body
    current_body=$(echo "$epic_data" | jq -r '.body // ""')
    
    if [ -z "$current_body" ]; then
        warning "Epic issue has no body to update"
        return 0
    fi
    
    # Create temp file with updated body
    local temp_body="/tmp/epic_body_$$"
    echo "$current_body" > "$temp_body"
    
    # Check off this task in the body
    # Look for patterns like: - [ ] #123 or - [ ] Task description #123
    sed -i.bak "s/- \[ \] \(.*\)#$issue_number\b/- [x] \\1#$issue_number/" "$temp_body"
    
    # Update epic issue
    if update_github_issue "$epic_issue_number" "" "$(cat "$temp_body")"; then
        success "Updated epic progress on GitHub"
    else
        warning "Failed to update epic task list on GitHub"
    fi
    
    # Cleanup
    rm -f "$temp_body" "$temp_body.bak"
}

# Update epic progress
update_epic_progress() {
    local epic_name="$1"
    
    info "Updating epic progress..."
    
    local epic_file=".claude/epics/$epic_name/epic.md"
    local total_tasks
    local closed_tasks
    local progress
    
    total_tasks=$(get_epic_task_count "$epic_name")
    closed_tasks=$(get_epic_task_count_by_status "$epic_name" "closed")
    
    if [ "$total_tasks" -gt 0 ]; then
        progress=$((closed_tasks * 100 / total_tasks))
    else
        progress=0
    fi
    
    local current_timestamp
    current_timestamp=$(get_current_iso_timestamp)
    
    # Update epic frontmatter
    update_frontmatter_bulk "$epic_file" \
        "progress:$progress" \
        "updated:$current_timestamp"
    
    success "Epic progress updated: ${progress}%"
}

# Reopen an issue
# Usage: reopen_issue "issue_number" ["reopening_reason"]
reopen_issue() {
    local issue_number="$1"
    local reopening_reason="$2"
    
    if [ -z "$issue_number" ]; then
        error_exit "Issue number is required"
    fi
    
    validate_issue_number "$issue_number"
    validate_github_auth
    
    info "Reopening issue #$issue_number..."
    
    # Find local task file
    local task_file
    task_file=$(find_task_file_for_issue "$issue_number")
    
    if [ -z "$task_file" ] || [ ! -f "$task_file" ]; then
        error_exit "No local task found for issue #$issue_number"
    fi
    
    local epic_name
    epic_name=$(find_epic_containing_issue "$issue_number")
    
    # Update local status to open
    local current_timestamp
    current_timestamp=$(get_current_iso_timestamp)
    
    update_frontmatter_bulk "$task_file" \
        "status:open" \
        "updated:$current_timestamp"
    
    # Reopen on GitHub
    local reopening_comment="🔄 Task reopened"
    
    if [ -n "$reopening_reason" ]; then
        reopening_comment="$reopening_comment

$reopening_reason"
    fi
    
    reopening_comment="$reopening_comment

---
Reopened at: $(format_timestamp_display "$current_timestamp")"
    
    if reopen_github_issue "$issue_number" "$reopening_comment"; then
        success "Reopened issue #$issue_number"
        
        # Update epic progress
        if [ -n "$epic_name" ]; then
            update_epic_progress "$epic_name"
        fi
        
        # Update epic task list (uncheck the box)
        if [ -n "$epic_name" ]; then
            update_epic_task_list_reopen "$epic_name" "$issue_number"
        fi
        
        echo "  Local: Task marked as open"
        echo "  GitHub: Issue reopened"
        echo ""
        echo "Task is now available for work."
    else
        error_exit "Failed to reopen GitHub issue #$issue_number"
    fi
}

# Update epic task list when reopening (uncheck the box)
update_epic_task_list_reopen() {
    local epic_name="$1"
    local issue_number="$2"
    
    info "Updating epic task list (unchecking completed task)..."
    
    # Get epic issue number
    local epic_file=".claude/epics/$epic_name/epic.md"
    local epic_github_url
    epic_github_url=$(get_frontmatter_field "$epic_file" "github")
    
    if [ -z "$epic_github_url" ]; then
        warning "Epic has no GitHub URL - cannot update task list"
        return 0
    fi
    
    local epic_issue_number
    epic_issue_number=$(extract_issue_number_from_url "$epic_github_url")
    
    if [ -z "$epic_issue_number" ]; then
        warning "Could not extract epic issue number"
        return 0
    fi
    
    # Get current epic body
    local epic_data
    epic_data=$(get_github_issue "$epic_issue_number")
    
    if [ -z "$epic_data" ]; then
        warning "Could not fetch epic issue #$epic_issue_number"
        return 0
    fi
    
    local current_body
    current_body=$(echo "$epic_data" | jq -r '.body // ""')
    
    if [ -z "$current_body" ]; then
        return 0
    fi
    
    # Create temp file with updated body
    local temp_body="/tmp/epic_body_$$"
    echo "$current_body" > "$temp_body"
    
    # Uncheck this task in the body
    sed -i.bak "s/- \[x\] \(.*\)#$issue_number\b/- [ ] \\1#$issue_number/" "$temp_body"
    
    # Update epic issue
    if update_github_issue "$epic_issue_number" "" "$(cat "$temp_body")"; then
        success "Updated epic task list on GitHub"
    else
        warning "Failed to update epic task list on GitHub"
    fi
    
    # Cleanup
    rm -f "$temp_body" "$temp_body.bak"
}

# Main function for command-line usage
main() {
    local command="$1"
    
    case "$command" in
        "close")
            shift
            close_issue "$@"
            ;;
        "reopen")
            shift
            reopen_issue "$@"
            ;;
        "help"|"--help"|"-h"|"")
            echo "Issue Management Script"
            echo "======================"
            echo ""
            echo "Usage: $0 <command> <issue_number> [completion_notes]"
            echo ""
            echo "Commands:"
            echo "  close <issue_number> [notes]     Close an issue with optional completion notes"
            echo "  reopen <issue_number> [reason]   Reopen a closed issue with optional reason"
            echo ""
            echo "Examples:"
            echo "  $0 close 1234 'Implemented authentication system with JWT tokens'"
            echo "  $0 reopen 1234 'Found a bug, needs additional work'"
            ;;
        *)
            error_exit "Unknown command: $command. Use 'help' for usage information."
            ;;
    esac
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi