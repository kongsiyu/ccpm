#!/bin/bash

# Epic Closing Script
# Marks an epic as complete when all tasks are done

# Source utility libraries
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

source "$LIB_DIR/error.sh"
source "$LIB_DIR/frontmatter.sh"
source "$LIB_DIR/datetime.sh"
source "$LIB_DIR/discovery.sh"
source "$LIB_DIR/github.sh"

set_strict_mode

# Main function to close an epic
# Usage: close_epic "epic_name" [--archive]
close_epic() {
    local epic_name="$1"
    local should_archive=false
    
    # Parse options
    while [[ $# -gt 1 ]]; do
        case $2 in
            --archive|-a)
                should_archive=true
                shift
                ;;
            *)
                error_exit "Unknown option: $2"
                ;;
        esac
    done
    
    if [ -z "$epic_name" ]; then
        error_exit "Epic name is required"
    fi
    
    validate_epic_name "$epic_name"
    validate_github_auth
    
    info "Closing epic: $epic_name"
    
    # Step 1: Verify all tasks are complete
    verify_all_tasks_complete "$epic_name"
    
    # Step 2: Update epic status
    update_epic_status "$epic_name"
    
    # Step 3: Update PRD status if linked
    update_linked_prd_status "$epic_name"
    
    # Step 4: Close epic on GitHub
    close_epic_on_github "$epic_name"
    
    # Step 5: Calculate epic duration
    local epic_duration
    epic_duration=$(calculate_epic_duration "$epic_name")
    
    # Step 6: Show completion summary
    show_completion_summary "$epic_name" "$epic_duration"
    
    # Step 7: Offer to archive
    if [ "$should_archive" = true ] || confirm "Archive completed epic?" "n"; then
        archive_epic "$epic_name"
    fi
    
    success "Epic closed: $epic_name"
    echo ""
    echo "Next epic: Run /pm:next to see priority work"
}

# Verify all tasks in the epic are closed
verify_all_tasks_complete() {
    local epic_name="$1"
    
    info "Verifying all tasks are complete..."
    
    local open_tasks=()
    
    while IFS= read -r task_file; do
        local task_status
        task_status=$(get_frontmatter_field "$task_file" "status" "open")
        
        if [ "$task_status" != "closed" ]; then
            local task_name
            task_name=$(get_frontmatter_field "$task_file" "name" "$(basename "$task_file" .md)")
            open_tasks+=("$(basename "$task_file" .md): $task_name")
        fi
    done < <(get_epic_task_files "$epic_name")
    
    if [ ${#open_tasks[@]} -gt 0 ]; then
        echo "❌ Cannot close epic. Open tasks remain:"
        for task in "${open_tasks[@]}"; do
            echo "  - $task"
        done
        echo ""
        echo "Close all tasks first or run: /pm:status $epic_name"
        exit 1
    fi
    
    success "All tasks are complete"
}

# Update epic status to completed
update_epic_status() {
    local epic_name="$1"
    
    info "Updating epic status..."
    
    local epic_file=".claude/epics/$epic_name/epic.md"
    local current_timestamp
    current_timestamp=$(get_current_iso_timestamp)
    
    # Update epic frontmatter
    update_frontmatter_bulk "$epic_file" \
        "status:completed" \
        "progress:100" \
        "updated:$current_timestamp" \
        "completed:$current_timestamp"
    
    success "Epic status updated to completed"
}

# Update linked PRD status
update_linked_prd_status() {
    local epic_name="$1"
    
    local epic_file=".claude/epics/$epic_name/epic.md"
    local prd_name
    prd_name=$(get_frontmatter_field "$epic_file" "prd")
    
    if [ -n "$prd_name" ]; then
        info "Updating linked PRD status..."
        
        local prd_file=".claude/prds/$prd_name.md"
        
        if [ -f "$prd_file" ]; then
            local current_timestamp
            current_timestamp=$(get_current_iso_timestamp)
            
            update_frontmatter_bulk "$prd_file" \
                "status:complete" \
                "updated:$current_timestamp" \
                "implemented:$current_timestamp"
            
            success "PRD status updated: $prd_name"
        else
            warning "Linked PRD file not found: $prd_file"
        fi
    fi
}

# Close epic on GitHub
close_epic_on_github() {
    local epic_name="$1"
    
    info "Closing epic on GitHub..."
    
    local epic_file=".claude/epics/$epic_name/epic.md"
    local epic_github_url
    epic_github_url=$(get_frontmatter_field "$epic_file" "github")
    
    if [ -z "$epic_github_url" ]; then
        warning "Epic has no GitHub URL - cannot close on GitHub"
        return 0
    fi
    
    local epic_issue_number
    epic_issue_number=$(extract_issue_number_from_url "$epic_github_url")
    
    if [ -z "$epic_issue_number" ]; then
        warning "Could not extract epic issue number from URL: $epic_github_url"
        return 0
    fi
    
    local total_tasks
    total_tasks=$(get_epic_task_count "$epic_name")
    
    local closing_comment="✅ Epic completed - all $total_tasks tasks done

This epic has been successfully completed with all tasks closed.

🎉 Ready for deployment and review."
    
    if close_github_issue "$epic_issue_number" "$closing_comment"; then
        success "Epic closed on GitHub"
    else
        error_exit "Failed to close epic on GitHub"
    fi
}

# Calculate epic duration
calculate_epic_duration() {
    local epic_name="$1"
    
    local epic_file=".claude/epics/$epic_name/epic.md"
    local created_timestamp
    local completed_timestamp
    
    created_timestamp=$(get_frontmatter_field "$epic_file" "created")
    completed_timestamp=$(get_frontmatter_field "$epic_file" "completed")
    
    if [ -n "$created_timestamp" ] && [ -n "$completed_timestamp" ]; then
        local created_ts
        local completed_ts
        
        created_ts=$(iso_to_timestamp "$created_timestamp")
        completed_ts=$(iso_to_timestamp "$completed_timestamp")
        
        if [ "$created_ts" != "0" ] && [ "$completed_ts" != "0" ]; then
            local duration_seconds=$((completed_ts - created_ts))
            local duration_days=$((duration_seconds / 86400))
            
            echo "$duration_days days"
            return 0
        fi
    fi
    
    echo "unknown"
}

# Show completion summary
show_completion_summary() {
    local epic_name="$1"
    local duration="$2"
    
    local total_tasks
    total_tasks=$(get_epic_task_count "$epic_name")
    
    echo ""
    echo "📊 Epic Completion Summary"
    echo "=========================="
    echo ""
    echo "Epic: $epic_name"
    echo "Tasks completed: $total_tasks"
    echo "Duration: $duration"
    echo ""
}

# Archive epic to .archived directory
archive_epic() {
    local epic_name="$1"
    
    info "Archiving epic..."
    
    local source_dir=".claude/epics/$epic_name"
    local archive_dir=".claude/epics/.archived"
    local target_dir="$archive_dir/$epic_name"
    
    # Create archive directory
    mkdir -p "$archive_dir"
    
    # Check if target already exists
    if [ -d "$target_dir" ]; then
        local timestamp
        timestamp=$(date +"%Y%m%d-%H%M%S")
        target_dir="${target_dir}-${timestamp}"
        warning "Archive target exists, using: $target_dir"
    fi
    
    # Move epic to archive
    mv "$source_dir" "$target_dir"
    
    # Create archive summary
    create_archive_summary "$epic_name" "$target_dir"
    
    success "Archived to $target_dir"
}

# Create archive summary
create_archive_summary() {
    local epic_name="$1"
    local archive_path="$2"
    
    local summary_file="$archive_path/ARCHIVE_INFO.md"
    local current_timestamp
    current_timestamp=$(get_current_iso_timestamp)
    
    {
        echo "# Archive Information"
        echo ""
        echo "**Epic:** $epic_name"
        echo "**Archived:** $(format_timestamp_display "$current_timestamp")"
        echo "**Status:** Completed"
        echo ""
        
        # Get epic details
        local epic_file="$archive_path/epic.md"
        if [ -f "$epic_file" ]; then
            local prd_name
            local created_date
            local completed_date
            
            prd_name=$(get_frontmatter_field "$epic_file" "prd" "N/A")
            created_date=$(get_frontmatter_field "$epic_file" "created")
            completed_date=$(get_frontmatter_field "$epic_file" "completed")
            
            echo "**Original PRD:** $prd_name"
            
            if [ -n "$created_date" ]; then
                echo "**Started:** $(format_timestamp_display "$created_date")"
            fi
            
            if [ -n "$completed_date" ]; then
                echo "**Completed:** $(format_timestamp_display "$completed_date")"
            fi
            
            echo ""
        fi
        
        # List completed tasks
        echo "## Tasks Completed"
        echo ""
        
        local task_count=0
        for task_file in "$archive_path"/[0-9]*.md; do
            [ -f "$task_file" ] || continue
            
            local task_name
            task_name=$(get_frontmatter_field "$task_file" "name" "$(basename "$task_file" .md)")
            
            echo "- $(basename "$task_file" .md): $task_name"
            task_count=$((task_count + 1))
        done
        
        echo ""
        echo "**Total Tasks:** $task_count"
        echo ""
        echo "---"
        echo ""
        echo "This epic was automatically archived by CCPM on completion."
        
    } > "$summary_file"
    
    info "Archive summary created: $summary_file"
}

# Reopen an epic (unarchive and set status back to active)
reopen_epic() {
    local epic_name="$1"
    
    if [ -z "$epic_name" ]; then
        error_exit "Epic name is required"
    fi
    
    info "Reopening epic: $epic_name"
    
    # Check if epic is archived
    local archived_path=".claude/epics/.archived/$epic_name"
    
    if [ -d "$archived_path" ]; then
        info "Unarchiving epic from .archived directory..."
        
        local target_path=".claude/epics/$epic_name"
        
        if [ -d "$target_path" ]; then
            error_exit "Epic directory already exists: $target_path"
        fi
        
        mv "$archived_path" "$target_path"
        success "Epic unarchived"
    else
        # Epic might just be marked as completed
        validate_epic_name "$epic_name"
    fi
    
    # Update epic status back to active
    local epic_file=".claude/epics/$epic_name/epic.md"
    local current_timestamp
    current_timestamp=$(get_current_iso_timestamp)
    
    # Get current progress (might not be 100% if tasks were reopened)
    local actual_progress
    actual_progress=$(get_epic_progress "$epic_name")
    
    update_frontmatter_bulk "$epic_file" \
        "status:active" \
        "progress:$actual_progress" \
        "updated:$current_timestamp"
    
    # Remove completed timestamp if it exists
    if grep -q "^completed:" "$epic_file"; then
        # Remove the completed line
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' '/^completed:/d' "$epic_file"
        else
            sed -i '/^completed:/d' "$epic_file"
        fi
    fi
    
    # Reopen epic on GitHub if it exists
    local epic_github_url
    epic_github_url=$(get_frontmatter_field "$epic_file" "github")
    
    if [ -n "$epic_github_url" ]; then
        local epic_issue_number
        epic_issue_number=$(extract_issue_number_from_url "$epic_github_url")
        
        if [ -n "$epic_issue_number" ]; then
            local reopening_comment="🔄 Epic reopened for additional work

Status: In Progress (${actual_progress}% complete)"
            
            if reopen_github_issue "$epic_issue_number" "$reopening_comment"; then
                success "Epic reopened on GitHub"
            else
                warning "Failed to reopen epic on GitHub"
            fi
        fi
    fi
    
    success "Epic reopened: $epic_name"
    echo "  Status: Active (${actual_progress}% complete)"
    echo "  Ready for continued development"
}

# Main function for command-line usage
main() {
    local command="$1"
    
    case "$command" in
        "close")
            shift
            close_epic "$@"
            ;;
        "reopen")
            shift
            reopen_epic "$@"
            ;;
        "help"|"--help"|"-h"|"")
            echo "Epic Management Script"
            echo "====================="
            echo ""
            echo "Usage: $0 <command> <epic_name> [options]"
            echo ""
            echo "Commands:"
            echo "  close <epic_name> [--archive]    Close an epic when all tasks are complete"
            echo "  reopen <epic_name>               Reopen a closed epic for additional work"
            echo ""
            echo "Options:"
            echo "  --archive, -a                    Automatically archive after closing"
            echo ""
            echo "Examples:"
            echo "  $0 close user-auth --archive"
            echo "  $0 reopen user-auth"
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