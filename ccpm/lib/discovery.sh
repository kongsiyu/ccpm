#!/bin/bash

# Discovery and Navigation Utility Library  
# Provides functions for finding and iterating through epics, tasks, and project structure

# Source required libraries
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/frontmatter.sh"

# Get list of all epic directories
# Usage: get_all_epic_dirs
# Returns: Space-separated list of epic directory paths
get_all_epic_dirs() {
    find .claude/epics -maxdepth 1 -type d -name "*" | grep -v "^\.claude/epics$" | grep -v "\.archived" | sort
}

# Get list of all epic names
# Usage: get_all_epic_names  
# Returns: Space-separated list of epic names
get_all_epic_names() {
    local epic_names=()
    
    for epic_dir in $(get_all_epic_dirs); do
        local epic_name
        epic_name=$(basename "$epic_dir")
        echo "$epic_name"
    done
}

# Check if epic exists
# Usage: epic_exists "epic_name"
# Returns: 0 if exists, 1 if not
epic_exists() {
    local epic_name="$1"
    
    if [ -z "$epic_name" ]; then
        return 1
    fi
    
    [ -f ".claude/epics/$epic_name/epic.md" ]
}

# Get all task files for an epic
# Usage: get_epic_task_files "epic_name"
# Returns: List of task file paths (one per line)
get_epic_task_files() {
    local epic_name="$1"
    
    if [ -z "$epic_name" ] || ! epic_exists "$epic_name"; then
        return 1
    fi
    
    local epic_dir=".claude/epics/$epic_name"
    
    for task_file in "$epic_dir"/[0-9]*.md; do
        [ -f "$task_file" ] && echo "$task_file"
    done | sort
}

# Count total tasks in an epic
# Usage: get_epic_task_count "epic_name"
# Returns: Number of tasks (0 if epic not found)
get_epic_task_count() {
    local epic_name="$1"
    
    if [ -z "$epic_name" ]; then
        echo "0"
        return 1
    fi
    
    get_epic_task_files "$epic_name" | wc -l | tr -d ' '
}

# Count tasks in an epic by status
# Usage: get_epic_task_count_by_status "epic_name" "status"
# Returns: Number of tasks with specified status
get_epic_task_count_by_status() {
    local epic_name="$1"
    local status="$2"
    
    if [ -z "$epic_name" ] || [ -z "$status" ]; then
        echo "0"
        return 1
    fi
    
    local count=0
    
    while IFS= read -r task_file; do
        [ -f "$task_file" ] || continue
        
        local task_status
        task_status=$(get_frontmatter_field "$task_file" "status" "open")
        
        if [ "$task_status" = "$status" ]; then
            count=$((count + 1))
        fi
    done < <(get_epic_task_files "$epic_name")
    
    echo "$count"
}

# Calculate epic progress percentage  
# Usage: get_epic_progress "epic_name"
# Returns: Progress percentage (0-100) or 0 if no tasks
get_epic_progress() {
    local epic_name="$1"
    
    if [ -z "$epic_name" ]; then
        echo "0"
        return 1
    fi
    
    local total_tasks
    local closed_tasks
    
    total_tasks=$(get_epic_task_count "$epic_name")
    closed_tasks=$(get_epic_task_count_by_status "$epic_name" "closed")
    
    if [ "$total_tasks" -eq 0 ]; then
        echo "0"
        return 0
    fi
    
    # Calculate percentage (bash integer arithmetic)
    local progress=$((closed_tasks * 100 / total_tasks))
    echo "$progress"
}

# Find epic that contains a specific issue number
# Usage: find_epic_containing_issue "123"
# Returns: Epic name or empty if not found
find_epic_containing_issue() {
    local issue_num="$1"
    
    if [ -z "$issue_num" ]; then
        return 1
    fi
    
    # First check for new naming convention (issue_number.md)
    for epic_dir in .claude/epics/*/; do
        [ -d "$epic_dir" ] || continue
        
        if [ -f "$epic_dir/$issue_num.md" ]; then
            basename "$epic_dir"
            return 0
        fi
    done
    
    # Check updates directory structure
    for epic_dir in .claude/epics/*/; do
        [ -d "$epic_dir" ] || continue
        
        if [ -d "$epic_dir/updates/$issue_num/" ]; then
            basename "$epic_dir"
            return 0
        fi
    done
    
    # Fallback to searching by GitHub URL in frontmatter
    for epic_dir in .claude/epics/*/; do
        [ -d "$epic_dir" ] || continue
        
        for task_file in "$epic_dir"/[0-9]*.md; do
            [ -f "$task_file" ] || continue
            
            if grep -q "github:.*issues/$issue_num" "$task_file"; then
                basename "$epic_dir"
                return 0
            fi
        done
    done
    
    return 1
}

# Find next available task number in an epic
# Usage: get_next_task_number "epic_name"
# Returns: Next available number (e.g., "004") or "001" if no tasks exist
get_next_task_number() {
    local epic_name="$1"
    
    if [ -z "$epic_name" ] || ! epic_exists "$epic_name"; then
        echo "001"
        return 1
    fi
    
    local epic_dir=".claude/epics/$epic_name"
    local max_num=0
    
    # Find highest existing task number
    for task_file in "$epic_dir"/[0-9]*.md; do
        [ -f "$task_file" ] || continue
        
        local filename
        filename=$(basename "$task_file" .md)
        
        # Extract numeric part (handle both formats: "001" and "1234")
        if [[ "$filename" =~ ^[0-9]+$ ]]; then
            local num=$((10#$filename))  # Force base 10 to handle leading zeros
            if [ "$num" -gt "$max_num" ]; then
                max_num="$num"
            fi
        fi
    done
    
    # Return next number with zero padding
    local next_num=$((max_num + 1))
    printf "%03d" "$next_num"
}

# Iterate through all task files with a callback function
# Usage: iterate_all_task_files "callback_function"
# Callback receives: task_file_path epic_name task_basename
iterate_all_task_files() {
    local callback="$1"
    
    if [ -z "$callback" ]; then
        echo "Error: Callback function required" >&2
        return 1
    fi
    
    for epic_dir in .claude/epics/*/; do
        [ -d "$epic_dir" ] || continue
        
        local epic_name
        epic_name=$(basename "$epic_dir")
        
        for task_file in "$epic_dir"/[0-9]*.md; do
            [ -f "$task_file" ] || continue
            
            local task_basename
            task_basename=$(basename "$task_file" .md)
            
            # Call the callback function with parameters
            "$callback" "$task_file" "$epic_name" "$task_basename"
        done
    done
}

# Find all tasks with specific status across all epics
# Usage: find_tasks_by_status "open"
# Returns: List of task file paths (one per line)
find_tasks_by_status() {
    local target_status="$1"
    
    if [ -z "$target_status" ]; then
        return 1
    fi
    
    local matching_tasks=()
    
    iterate_all_task_files() {
        local task_file="$1"
        local epic_name="$2"
        local task_basename="$3"
        
        local task_status
        task_status=$(get_frontmatter_field "$task_file" "status" "open")
        
        if [ "$task_status" = "$target_status" ]; then
            echo "$task_file"
        fi
    }
    
    iterate_all_task_files "iterate_all_task_files"
}

# Find all tasks that are ready to work on (open with satisfied dependencies)
# Usage: find_available_tasks
# Returns: List of task file paths (one per line) 
find_available_tasks() {
    # Source dependencies library if not already loaded
    if ! type get_task_dependencies >/dev/null 2>&1; then
        source "$SCRIPT_DIR/dependencies.sh"
    fi
    
    iterate_all_task_files() {
        local task_file="$1"
        local epic_name="$2"
        local task_basename="$3"
        
        # Check if task is open
        local task_status
        task_status=$(get_frontmatter_field "$task_file" "status" "open")
        
        if [ "$task_status" != "open" ]; then
            return 0
        fi
        
        # Check if dependencies are satisfied
        local epic_dir=".claude/epics/$epic_name"
        
        if are_dependencies_satisfied "$task_file" "$epic_dir"; then
            echo "$task_file"
        fi
    }
    
    iterate_all_task_files "iterate_all_task_files"
}

# Find all tasks that are blocked by dependencies
# Usage: find_blocked_tasks
# Returns: List of task file paths (one per line)
find_blocked_tasks() {
    # Source dependencies library if not already loaded
    if ! type get_task_dependencies >/dev/null 2>&1; then
        source "$SCRIPT_DIR/dependencies.sh"
    fi
    
    iterate_all_task_files() {
        local task_file="$1"
        local epic_name="$2" 
        local task_basename="$3"
        
        # Check if task is open
        local task_status
        task_status=$(get_frontmatter_field "$task_file" "status" "open")
        
        if [ "$task_status" != "open" ]; then
            return 0
        fi
        
        # Check if task has dependencies and they're not satisfied
        if has_dependencies "$task_file"; then
            local epic_dir=".claude/epics/$epic_name"
            
            if ! are_dependencies_satisfied "$task_file" "$epic_dir"; then
                echo "$task_file"
            fi
        fi
    }
    
    iterate_all_task_files "iterate_all_task_files"
}

# Get all tasks in progress (status: in-progress)
# Usage: find_in_progress_tasks
# Returns: List of task file paths (one per line)
find_in_progress_tasks() {
    find_tasks_by_status "in-progress"
}

# Find all parallel tasks in an epic
# Usage: find_parallel_tasks "epic_name"
# Returns: List of task file paths (one per line)
find_parallel_tasks() {
    local epic_name="$1"
    
    if [ -z "$epic_name" ]; then
        return 1
    fi
    
    while IFS= read -r task_file; do
        [ -f "$task_file" ] || continue
        
        local parallel
        parallel=$(get_frontmatter_field "$task_file" "parallel" "false")
        
        if [ "$parallel" = "true" ]; then
            echo "$task_file"
        fi
    done < <(get_epic_task_files "$epic_name")
}

# Get epic summary information
# Usage: get_epic_summary "epic_name"
# Returns: Multi-line summary with epic stats
get_epic_summary() {
    local epic_name="$1"
    
    if [ -z "$epic_name" ] || ! epic_exists "$epic_name"; then
        echo "Epic not found: $epic_name"
        return 1
    fi
    
    local total_tasks
    local open_tasks
    local closed_tasks  
    local in_progress_tasks
    local progress
    
    total_tasks=$(get_epic_task_count "$epic_name")
    open_tasks=$(get_epic_task_count_by_status "$epic_name" "open")
    closed_tasks=$(get_epic_task_count_by_status "$epic_name" "closed")
    in_progress_tasks=$(get_epic_task_count_by_status "$epic_name" "in-progress")
    progress=$(get_epic_progress "$epic_name")
    
    echo "Epic: $epic_name"
    echo "Progress: ${progress}% (${closed_tasks}/${total_tasks} tasks complete)"
    echo "Open: $open_tasks"
    echo "In Progress: $in_progress_tasks"  
    echo "Closed: $closed_tasks"
    echo "Total: $total_tasks"
}

# Find stale files (older than specified days with no updates)
# Usage: find_stale_files "30" ["status_filter"]  
# Returns: List of file paths (one per line)
find_stale_files() {
    local max_age_days="$1"
    local status_filter="${2:-}"
    
    if [ -z "$max_age_days" ]; then
        max_age_days=30
    fi
    
    # Source datetime library if not already loaded
    if ! type get_file_age_days >/dev/null 2>&1; then
        source "$SCRIPT_DIR/datetime.sh"
    fi
    
    iterate_all_task_files() {
        local task_file="$1"
        local epic_name="$2"
        local task_basename="$3"
        
        # Apply status filter if specified
        if [ -n "$status_filter" ]; then
            local task_status
            task_status=$(get_frontmatter_field "$task_file" "status" "open")
            
            if [ "$task_status" != "$status_filter" ]; then
                return 0
            fi
        fi
        
        # Check if file is stale
        if is_file_older_than_days "$task_file" "$max_age_days" "updated"; then
            echo "$task_file"
        fi
    }
    
    iterate_all_task_files "iterate_all_task_files"
}