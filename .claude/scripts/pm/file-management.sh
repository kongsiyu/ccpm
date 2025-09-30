#!/bin/bash

# File Management Utility Script
# Handles file renaming, organizing, and restructuring operations

# Source utility libraries
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

source "$LIB_DIR/error.sh"
source "$LIB_DIR/frontmatter.sh"
source "$LIB_DIR/datetime.sh"
source "$LIB_DIR/discovery.sh"
source "$LIB_DIR/github.sh"

set_strict_mode

# Rename task files based on GitHub issue numbers
# Usage: rename_task_files_by_issue_number "epic_name" [--dry-run]
rename_task_files_by_issue_number() {
    local epic_name="$1"
    local dry_run=false
    
    # Parse options
    while [[ $# -gt 1 ]]; do
        case $2 in
            --dry-run|-n)
                dry_run=true
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
    
    local epic_dir=".claude/epics/$epic_name"
    local renamed_count=0
    
    info "Scanning task files in $epic_name for GitHub issue numbers..."
    
    for task_file in "$epic_dir"/[0-9]*.md; do
        [ -f "$task_file" ] || continue
        
        # Extract issue number from GitHub URL in frontmatter
        local github_url
        github_url=$(get_frontmatter_field "$task_file" "github")
        
        if [ -n "$github_url" ]; then
            local issue_num
            issue_num=$(extract_issue_number_from_url "$github_url")
            
            if [ -n "$issue_num" ]; then
                local current_filename
                current_filename=$(basename "$task_file" .md)
                local target_filename="$issue_num.md"
                local target_path="$epic_dir/$target_filename"
                
                # Check if rename is needed
                if [ "$current_filename.md" != "$target_filename" ]; then
                    if [ -f "$target_path" ] && [ "$target_path" != "$task_file" ]; then
                        warning "Target file already exists: $target_path (skipping $task_file)"
                        continue
                    fi
                    
                    if [ "$dry_run" = true ]; then
                        echo "Would rename: $task_file → $target_path"
                    else
                        mv "$task_file" "$target_path"
                        success "Renamed: $current_filename.md → $target_filename"
                        
                        # Update any references in dependencies
                        update_dependency_references "$epic_dir" "$current_filename" "$issue_num"
                    fi
                    
                    renamed_count=$((renamed_count + 1))
                fi
            else
                warning "Could not extract issue number from GitHub URL in $task_file"
            fi
        fi
    done
    
    if [ "$dry_run" = true ]; then
        info "Dry run complete. Would rename $renamed_count files."
    else
        success "Renamed $renamed_count task files based on issue numbers"
    fi
    
    return 0
}

# Update dependency references after renaming
# Usage: update_dependency_references "epic_dir" "old_task_id" "new_task_id"
update_dependency_references() {
    local epic_dir="$1"
    local old_id="$2"
    local new_id="$3"
    
    if ! type get_task_dependencies >/dev/null 2>&1; then
        source "$LIB_DIR/dependencies.sh"
    fi
    
    # Update all task files that reference the old ID
    for task_file in "$epic_dir"/[0-9]*.md; do
        [ -f "$task_file" ] || continue
        
        local deps
        deps=$(get_task_dependencies "$task_file")
        
        if echo "$deps" | grep -q "\\b$old_id\\b"; then
            # Replace old ID with new ID in dependencies
            local new_deps
            new_deps=$(echo "$deps" | sed "s/\\b$old_id\\b/$new_id/g")
            
            update_task_dependencies "$task_file" "$new_deps"
            info "Updated dependencies in $(basename "$task_file"): $old_id → $new_id"
        fi
    done
}

# Organize files by status (move closed tasks to subdirectory)
# Usage: organize_files_by_status "epic_name" [--dry-run]
organize_files_by_status() {
    local epic_name="$1"
    local dry_run=false
    
    # Parse options
    while [[ $# -gt 1 ]]; do
        case $2 in
            --dry-run|-n)
                dry_run=true
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
    
    local epic_dir=".claude/epics/$epic_name"
    local closed_dir="$epic_dir/closed"
    local moved_count=0
    
    # Create closed directory if it doesn't exist
    if [ "$dry_run" = false ]; then
        mkdir -p "$closed_dir"
    fi
    
    info "Organizing task files by status in $epic_name..."
    
    for task_file in "$epic_dir"/[0-9]*.md; do
        [ -f "$task_file" ] || continue
        
        local task_status
        task_status=$(get_frontmatter_field "$task_file" "status" "open")
        
        if [ "$task_status" = "closed" ]; then
            local filename
            filename=$(basename "$task_file")
            local target_path="$closed_dir/$filename"
            
            if [ "$dry_run" = true ]; then
                echo "Would move: $task_file → $target_path"
            else
                mv "$task_file" "$target_path"
                success "Moved closed task: $filename → closed/"
            fi
            
            moved_count=$((moved_count + 1))
        fi
    done
    
    if [ "$dry_run" = true ]; then
        info "Dry run complete. Would move $moved_count closed tasks."
    else
        success "Moved $moved_count closed tasks to closed/ subdirectory"
    fi
    
    return 0
}

# Standardize file naming (ensure proper zero-padding and format)
# Usage: standardize_file_naming "epic_name" [--dry-run]
standardize_file_naming() {
    local epic_name="$1"
    local dry_run=false
    
    # Parse options
    while [[ $# -gt 1 ]]; do
        case $2 in
            --dry-run|-n)
                dry_run=true
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
    
    local epic_dir=".claude/epics/$epic_name"
    local renamed_count=0
    
    info "Standardizing file names in $epic_name..."
    
    for task_file in "$epic_dir"/[0-9]*.md; do
        [ -f "$task_file" ] || continue
        
        local filename
        filename=$(basename "$task_file" .md)
        
        # Check if this is a sequential number (not an issue number)
        if [[ "$filename" =~ ^[0-9]{1,3}$ ]] && [ ${#filename} -lt 3 ]; then
            # Needs zero-padding
            local padded_filename
            padded_filename=$(printf "%03d" "$((10#$filename))")
            local target_path="$epic_dir/$padded_filename.md"
            
            if [ "$target_path" != "$task_file" ]; then
                if [ -f "$target_path" ]; then
                    warning "Target file already exists: $target_path (skipping $task_file)"
                    continue
                fi
                
                if [ "$dry_run" = true ]; then
                    echo "Would rename: $task_file → $target_path"
                else
                    mv "$task_file" "$target_path"
                    success "Standardized: $filename.md → $padded_filename.md"
                    
                    # Update dependency references
                    update_dependency_references "$epic_dir" "$filename" "$padded_filename"
                fi
                
                renamed_count=$((renamed_count + 1))
            fi
        fi
    done
    
    if [ "$dry_run" = true ]; then
        info "Dry run complete. Would standardize $renamed_count filenames."
    else
        success "Standardized $renamed_count filenames"
    fi
    
    return 0
}

# Batch rename tasks based on GitHub sync
# Usage: batch_rename_after_github_sync "epic_name" [--dry-run]
batch_rename_after_github_sync() {
    local epic_name="$1"
    
    info "Processing batch rename after GitHub sync for: $epic_name"
    
    # First rename based on issue numbers
    rename_task_files_by_issue_number "$epic_name" "$@"
    
    # Then standardize any remaining sequential numbers
    standardize_file_naming "$epic_name" "$@"
    
    success "Batch rename complete for $epic_name"
}

# Find and fix naming inconsistencies across all epics
# Usage: fix_naming_inconsistencies [--dry-run]
fix_naming_inconsistencies() {
    local dry_run=false
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run|-n)
                dry_run=true
                shift
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
    
    info "Scanning all epics for naming inconsistencies..."
    
    local total_fixes=0
    
    for epic_dir in .claude/epics/*/; do
        [ -d "$epic_dir" ] || continue
        
        # Skip archived epics
        if [[ "$epic_dir" == *"/.archived/"* ]]; then
            continue
        fi
        
        local epic_name
        epic_name=$(basename "$epic_dir")
        
        # Check if epic has tasks
        if ls "$epic_dir"/[0-9]*.md >/dev/null 2>&1; then
            info "Checking $epic_name..."
            
            # Fix issue-number based naming
            local args=()
            [ "$dry_run" = true ] && args+=("--dry-run")
            
            rename_task_files_by_issue_number "$epic_name" "${args[@]}"
            standardize_file_naming "$epic_name" "${args[@]}"
        fi
    done
    
    success "Naming consistency check complete"
}

# Create backup before bulk operations
# Usage: create_backup "epic_name" "operation_name"
create_backup() {
    local epic_name="$1"
    local operation="$2"
    
    if [ -z "$epic_name" ] || [ -z "$operation" ]; then
        error_exit "Both epic name and operation name required for backup"
    fi
    
    local backup_dir="/tmp/ccpm-backup-$(date +%s)"
    local source_dir=".claude/epics/$epic_name"
    
    mkdir -p "$backup_dir"
    cp -r "$source_dir" "$backup_dir/"
    
    info "Created backup for $operation: $backup_dir"
    echo "$backup_dir"
}

# Restore from backup
# Usage: restore_backup "backup_path" "epic_name"
restore_backup() {
    local backup_path="$1"
    local epic_name="$2"
    
    if [ -z "$backup_path" ] || [ -z "$epic_name" ]; then
        error_exit "Both backup path and epic name required for restore"
    fi
    
    if [ ! -d "$backup_path" ]; then
        error_exit "Backup directory not found: $backup_path"
    fi
    
    local target_dir=".claude/epics/$epic_name"
    
    if confirm "This will overwrite current epic data. Continue?" "n"; then
        rm -rf "$target_dir"
        cp -r "$backup_path/$epic_name" "$target_dir"
        success "Restored epic from backup: $backup_path"
    else
        info "Restore cancelled"
    fi
}

# Main function for command-line usage
main() {
    local command="$1"
    shift
    
    case "$command" in
        "rename-by-issue")
            rename_task_files_by_issue_number "$@"
            ;;
        "organize-by-status")
            organize_files_by_status "$@"
            ;;
        "standardize-names")
            standardize_file_naming "$@"
            ;;
        "batch-rename")
            batch_rename_after_github_sync "$@"
            ;;
        "fix-inconsistencies")
            fix_naming_inconsistencies "$@"
            ;;
        "create-backup")
            create_backup "$@"
            ;;
        "restore-backup")
            restore_backup "$@"
            ;;
        "help"|"--help"|"-h"|"")
            echo "File Management Utility"
            echo "======================"
            echo ""
            echo "Usage: $0 <command> [options]"
            echo ""
            echo "Commands:"
            echo "  rename-by-issue <epic_name>      Rename task files based on GitHub issue numbers"
            echo "  organize-by-status <epic_name>   Move closed tasks to subdirectory"
            echo "  standardize-names <epic_name>    Ensure proper zero-padding for sequential files"
            echo "  batch-rename <epic_name>         Complete rename process after GitHub sync"
            echo "  fix-inconsistencies              Fix naming issues across all epics"
            echo "  create-backup <epic> <operation> Create backup before bulk operations"
            echo "  restore-backup <path> <epic>     Restore epic from backup"
            echo ""
            echo "Options:"
            echo "  --dry-run, -n                    Show what would be done without making changes"
            echo ""
            echo "Examples:"
            echo "  $0 batch-rename user-auth --dry-run"
            echo "  $0 fix-inconsistencies"
            echo "  $0 organize-by-status user-auth"
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