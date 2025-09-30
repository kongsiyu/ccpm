#!/bin/bash

# System Cleanup Script
# Cleans up completed work and archives old epics

# Source utility libraries
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

source "$LIB_DIR/error.sh"
source "$LIB_DIR/frontmatter.sh"
source "$LIB_DIR/datetime.sh"
source "$LIB_DIR/discovery.sh"

set_strict_mode

# Configuration
STALE_DAYS="${STALE_DAYS:-30}"
ARCHIVE_DIR=".claude/epics/.archived"

# Parse command line arguments
DRY_RUN=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--dry-run] [--verbose]"
            echo "  --dry-run    Show what would be cleaned without doing it"
            echo "  --verbose    Show detailed output"
            exit 0
            ;;
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

# Validate prerequisites
validate_directory_structure

# Initialize counters and lists
declare -a completed_epics=()
declare -a stale_progress_files=()
declare -a empty_directories=()
total_size=0

# Find completed epics
find_completed_epics() {
    info "Scanning for completed epics..."
    
    for epic_dir in .claude/epics/*/; do
        [ -d "$epic_dir" ] || continue
        
        # Skip already archived epics
        if [[ "$epic_dir" == *"/.archived/"* ]]; then
            continue
        fi
        
        local epic_name
        epic_name=$(basename "$epic_dir")
        local epic_file="$epic_dir/epic.md"
        
        [ -f "$epic_file" ] || continue
        
        # Check if epic is completed
        local epic_status
        epic_status=$(get_frontmatter_field "$epic_file" "status" "open")
        
        if [ "$epic_status" = "completed" ]; then
            # Check if all tasks are closed
            local open_tasks
            open_tasks=$(get_epic_task_count_by_status "$epic_name" "open")
            
            if [ "$open_tasks" -eq 0 ]; then
                # Check last update time
                local updated
                updated=$(get_frontmatter_field "$epic_file" "updated")
                
                if [ -n "$updated" ]; then
                    local age_days
                    age_days=$(get_file_age_days "$epic_file" "updated")
                    
                    if [ "$age_days" -gt "$STALE_DAYS" ]; then
                        completed_epics+=("$epic_name:$age_days")
                        
                        # Calculate size
                        local dir_size
                        dir_size=$(du -sk "$epic_dir" 2>/dev/null | cut -f1)
                        total_size=$((total_size + dir_size))
                        
                        [ "$VERBOSE" = true ] && echo "  Found completed epic: $epic_name ($age_days days old, ${dir_size}KB)"
                    fi
                fi
            else
                [ "$VERBOSE" = true ] && warning "Epic $epic_name marked complete but has $open_tasks open tasks"
            fi
        fi
    done
    
    info "Found ${#completed_epics[@]} completed epics to archive"
}

# Find stale progress files
find_stale_progress() {
    info "Scanning for stale progress files..."
    
    for epic_dir in .claude/epics/*/; do
        [ -d "$epic_dir" ] || continue
        
        local updates_dir="$epic_dir/updates"
        [ -d "$updates_dir" ] || continue
        
        for issue_dir in "$updates_dir"/*/; do
            [ -d "$issue_dir" ] || continue
            
            local issue_num
            issue_num=$(basename "$issue_dir")
            
            # Check if corresponding task is closed and old
            local task_file
            task_file=$(find_task_file_for_issue "$issue_num" 2>/dev/null)
            
            if [ -n "$task_file" ] && [ -f "$task_file" ]; then
                local task_status
                task_status=$(get_frontmatter_field "$task_file" "status" "open")
                
                if [ "$task_status" = "closed" ]; then
                    local age_days
                    age_days=$(get_file_age_days "$task_file" "updated")
                    
                    if [ "$age_days" -gt "$STALE_DAYS" ]; then
                        stale_progress_files+=("$issue_dir")
                        
                        # Calculate size
                        local dir_size
                        dir_size=$(du -sk "$issue_dir" 2>/dev/null | cut -f1)
                        total_size=$((total_size + dir_size))
                        
                        [ "$VERBOSE" = true ] && echo "  Found stale progress: $issue_dir ($age_days days old)"
                    fi
                fi
            else
                # Progress directory exists but no corresponding task - likely orphaned
                stale_progress_files+=("$issue_dir")
                local dir_size
                dir_size=$(du -sk "$issue_dir" 2>/dev/null | cut -f1)
                total_size=$((total_size + dir_size))
                
                [ "$VERBOSE" = true ] && echo "  Found orphaned progress: $issue_dir"
            fi
        done
    done
    
    info "Found ${#stale_progress_files[@]} stale progress files"
}

# Find empty directories
find_empty_directories() {
    info "Scanning for empty directories..."
    
    while IFS= read -r -d '' dir; do
        # Skip the base directories we need to keep
        case "$dir" in
            ".claude/epics"|".claude/epics/.archived"|".claude"*)
                continue
                ;;
        esac
        
        empty_directories+=("$dir")
        [ "$VERBOSE" = true ] && echo "  Found empty directory: $dir"
    done < <(find .claude/epics -type d -empty -print0 2>/dev/null)
    
    info "Found ${#empty_directories[@]} empty directories"
}

# Show cleanup plan
show_cleanup_plan() {
    echo ""
    echo "🧹 Cleanup Plan"
    echo "==============="
    echo ""
    
    if [ ${#completed_epics[@]} -gt 0 ]; then
        echo "Completed Epics to Archive:"
        for epic_info in "${completed_epics[@]}"; do
            local epic_name="${epic_info%:*}"
            local days="${epic_info#*:}"
            echo "  $epic_name - Completed $days days ago"
        done
        echo ""
    fi
    
    if [ ${#stale_progress_files[@]} -gt 0 ]; then
        echo "Stale Progress to Remove:"
        echo "  ${#stale_progress_files[@]} progress files for closed issues"
        if [ "$VERBOSE" = true ]; then
            for progress_dir in "${stale_progress_files[@]}"; do
                echo "    $progress_dir"
            done
        fi
        echo ""
    fi
    
    if [ ${#empty_directories[@]} -gt 0 ]; then
        echo "Empty Directories:"
        for dir in "${empty_directories[@]}"; do
            echo "  $dir"
        done
        echo ""
    fi
    
    if [ $total_size -gt 0 ]; then
        echo "Space to Recover: ~${total_size}KB"
        echo ""
    fi
    
    if [ "$DRY_RUN" = true ]; then
        echo "This is a dry run. No changes made."
        return 0
    fi
    
    # Ask for confirmation if not dry run and items found
    local total_items=$((${#completed_epics[@]} + ${#stale_progress_files[@]} + ${#empty_directories[@]}))
    
    if [ $total_items -eq 0 ]; then
        success "System is already clean. Nothing to do."
        return 0
    fi
    
    if ! confirm "Proceed with cleanup?" "n"; then
        info "Cleanup cancelled by user"
        return 0
    fi
    
    return 1  # Proceed with cleanup
}

# Execute cleanup
execute_cleanup() {
    echo ""
    info "Starting cleanup operations..."
    
    # Create archive directory
    mkdir -p "$ARCHIVE_DIR"
    
    local archived_count=0
    local removed_files=0
    local removed_dirs=0
    
    # Archive completed epics
    if [ ${#completed_epics[@]} -gt 0 ]; then
        info "Archiving completed epics..."
        
        for epic_info in "${completed_epics[@]}"; do
            local epic_name="${epic_info%:*}"
            local epic_dir=".claude/epics/$epic_name"
            local archive_path="$ARCHIVE_DIR/$epic_name"
            
            if [ -d "$epic_dir" ]; then
                mv "$epic_dir" "$archive_path"
                success "Archived: $epic_name"
                archived_count=$((archived_count + 1))
            fi
        done
    fi
    
    # Remove stale progress files
    if [ ${#stale_progress_files[@]} -gt 0 ]; then
        info "Removing stale progress files..."
        
        for progress_dir in "${stale_progress_files[@]}"; do
            if [ -d "$progress_dir" ]; then
                rm -rf "$progress_dir"
                removed_files=$((removed_files + 1))
                [ "$VERBOSE" = true ] && echo "  Removed: $progress_dir"
            fi
        done
        
        success "Removed $removed_files stale progress directories"
    fi
    
    # Remove empty directories
    if [ ${#empty_directories[@]} -gt 0 ]; then
        info "Removing empty directories..."
        
        for dir in "${empty_directories[@]}"; do
            if [ -d "$dir" ] && [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
                rmdir "$dir" 2>/dev/null && {
                    removed_dirs=$((removed_dirs + 1))
                    [ "$VERBOSE" = true ] && echo "  Removed: $dir"
                }
            fi
        done
        
        success "Removed $removed_dirs empty directories"
    fi
    
    # Create archive log
    if [ $archived_count -gt 0 ]; then
        create_archive_log "$archived_count"
    fi
    
    # Show final summary
    echo ""
    success "Cleanup Complete"
    echo ""
    echo "Archived:"
    echo "  $archived_count completed epics"
    echo ""
    echo "Removed:"
    echo "  $removed_files stale files"
    echo "  $removed_dirs empty directories"
    echo ""
    echo "Space recovered: ${total_size}KB"
    echo ""
    echo "System is clean and organized."
}

# Create archive log
create_archive_log() {
    local archived_count="$1"
    local log_file="$ARCHIVE_DIR/archive-log.md"
    local current_date
    current_date=$(get_current_iso_timestamp)
    
    # Append to existing log or create new one
    {
        if [ ! -f "$log_file" ]; then
            echo "# Archive Log"
            echo ""
        fi
        
        echo "## $(format_timestamp_display "$current_date")"
        echo "- Archived: $archived_count completed epics"
        echo "- Removed: ${#stale_progress_files[@]} stale progress files"
        echo "- Cleaned: ${#empty_directories[@]} empty directories"
        echo "- Space recovered: ${total_size}KB"
        echo ""
        
        # List archived epics
        if [ ${#completed_epics[@]} -gt 0 ]; then
            echo "### Archived Epics:"
            for epic_info in "${completed_epics[@]}"; do
                local epic_name="${epic_info%:*}"
                local days="${epic_info#*:}"
                echo "- $epic_name (completed $days days ago)"
            done
            echo ""
        fi
        
    } >> "$log_file"
    
    info "Archive log updated: $log_file"
}

# Main execution
main() {
    echo "🧹 CCPM System Cleanup"
    echo "====================="
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        info "Running in DRY-RUN mode - no changes will be made"
        echo ""
    fi
    
    # Perform scans
    find_completed_epics
    find_stale_progress
    find_empty_directories
    
    # Show plan and get confirmation
    if show_cleanup_plan; then
        return 0  # Dry run or nothing to do
    fi
    
    # Execute cleanup
    execute_cleanup
}

# Run main function
main "$@"