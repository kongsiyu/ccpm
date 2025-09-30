#!/bin/bash

# Dependency Parsing Utility Library
# Provides functions for parsing and validating task dependencies from frontmatter

# Source frontmatter library for field extraction
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/frontmatter.sh"

# Get task dependencies as space-separated list
# Usage: get_task_dependencies "task_file.md"
# Returns: Space-separated dependency list (e.g., "001 002 003") or empty string
get_task_dependencies() {
    local file="$1"
    
    if [ ! -f "$file" ]; then
        echo ""
        return 1
    fi
    
    # Extract dependencies line
    local deps_line
    deps_line=$(grep "^depends_on:" "$file" 2>/dev/null | head -1)
    
    if [ -z "$deps_line" ]; then
        echo ""
        return 0
    fi
    
    # Extract and clean dependencies
    local deps
    deps=$(echo "$deps_line" | sed 's/^depends_on:[[:space:]]*//')
    
    # Remove brackets
    deps=$(echo "$deps" | sed 's/^\[//' | sed 's/\]$//')
    
    # Convert commas to spaces
    deps=$(echo "$deps" | sed 's/,/ /g')
    
    # Trim whitespace
    deps=$(echo "$deps" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    
    # Normalize multiple spaces to single spaces
    deps=$(echo "$deps" | tr -s ' ')
    
    # Handle empty/malformed cases
    if [ -z "$deps" ] || [ "$deps" = "depends_on:" ]; then
        echo ""
    else
        echo "$deps"
    fi
    
    return 0
}

# Get task dependencies as bash array
# Usage: 
#   deps_array=($(get_task_dependencies_array "task_file.md"))
# Returns: Dependencies as separate elements suitable for array assignment
get_task_dependencies_array() {
    local file="$1"
    local deps_string
    
    deps_string=$(get_task_dependencies "$file")
    
    if [ -n "$deps_string" ]; then
        echo "$deps_string"
    fi
}

# Check if a task has any dependencies
# Usage: has_dependencies "task_file.md"
# Returns: 0 if has dependencies, 1 if no dependencies
has_dependencies() {
    local file="$1"
    local deps
    
    deps=$(get_task_dependencies "$file")
    [ -n "$deps" ]
}

# Check if all dependencies for a task are satisfied (closed)
# Usage: are_dependencies_satisfied "task_file.md" "epic_dir"
# Returns: 0 if all dependencies satisfied, 1 if any are still open/missing
are_dependencies_satisfied() {
    local task_file="$1"
    local epic_dir="$2"
    
    if [ ! -f "$task_file" ] || [ ! -d "$epic_dir" ]; then
        return 1
    fi
    
    local deps
    deps=$(get_task_dependencies "$task_file")
    
    # No dependencies means satisfied
    if [ -z "$deps" ]; then
        return 0
    fi
    
    # Check each dependency
    for dep in $deps; do
        local dep_file="$epic_dir/$dep.md"
        
        # Dependency file must exist
        if [ ! -f "$dep_file" ]; then
            return 1
        fi
        
        # Dependency must be closed
        local dep_status
        dep_status=$(get_frontmatter_field "$dep_file" "status" "open")
        if [ "$dep_status" != "closed" ]; then
            return 1
        fi
    done
    
    return 0
}

# Get list of unsatisfied dependencies
# Usage: get_unsatisfied_dependencies "task_file.md" "epic_dir"
# Returns: Space-separated list of dependency IDs that are not satisfied
get_unsatisfied_dependencies() {
    local task_file="$1"
    local epic_dir="$2"
    local unsatisfied=""
    
    if [ ! -f "$task_file" ] || [ ! -d "$epic_dir" ]; then
        echo ""
        return 1
    fi
    
    local deps
    deps=$(get_task_dependencies "$task_file")
    
    if [ -z "$deps" ]; then
        echo ""
        return 0
    fi
    
    # Check each dependency
    for dep in $deps; do
        local dep_file="$epic_dir/$dep.md"
        
        # Check if dependency file exists and is closed
        if [ ! -f "$dep_file" ]; then
            unsatisfied="$unsatisfied $dep"
        else
            local dep_status
            dep_status=$(get_frontmatter_field "$dep_file" "status" "open")
            if [ "$dep_status" != "closed" ]; then
                unsatisfied="$unsatisfied $dep"
            fi
        fi
    done
    
    # Trim leading space
    echo "$unsatisfied" | sed 's/^[[:space:]]*//'
}

# Validate dependency references (check for circular dependencies, missing refs)
# Usage: validate_task_dependencies "epic_dir"
# Returns: 0 if all dependencies valid, 1 if issues found
# Outputs: Warning messages for any issues found
validate_task_dependencies() {
    local epic_dir="$1"
    local issues_found=0
    
    if [ ! -d "$epic_dir" ]; then
        echo "Error: Epic directory $epic_dir does not exist" >&2
        return 1
    fi
    
    # Check each task file
    for task_file in "$epic_dir"/[0-9]*.md; do
        [ -f "$task_file" ] || continue
        
        local task_id
        task_id=$(basename "$task_file" .md)
        
        local deps
        deps=$(get_task_dependencies "$task_file")
        
        if [ -n "$deps" ]; then
            # Check for self-dependency
            for dep in $deps; do
                if [ "$dep" = "$task_id" ]; then
                    echo "Warning: Task $task_id depends on itself" >&2
                    issues_found=1
                fi
                
                # Check if dependency file exists
                if [ ! -f "$epic_dir/$dep.md" ]; then
                    echo "Warning: Task $task_id depends on missing task $dep" >&2
                    issues_found=1
                fi
            done
        fi
    done
    
    # TODO: Check for circular dependencies (would require graph traversal)
    # For now, just check for direct circular references
    
    return $issues_found
}

# Update task dependencies
# Usage: update_task_dependencies "task_file.md" "001 002 003"
# Returns: 0 on success, 1 on failure
update_task_dependencies() {
    local file="$1"
    local deps_string="$2"
    
    if [ ! -f "$file" ]; then
        echo "Error: File $file does not exist" >&2
        return 1
    fi
    
    # Format as YAML array
    if [ -n "$deps_string" ]; then
        local formatted_deps="[$deps_string]"
        # Replace spaces with commas for YAML array format
        formatted_deps=$(echo "$formatted_deps" | sed 's/ /, /g')
        update_frontmatter_field "$file" "depends_on" "$formatted_deps"
    else
        update_frontmatter_field "$file" "depends_on" "[]"
    fi
    
    return 0
}

# Add a dependency to a task
# Usage: add_task_dependency "task_file.md" "dependency_id"
# Returns: 0 on success, 1 on failure
add_task_dependency() {
    local file="$1"
    local new_dep="$2"
    
    if [ ! -f "$file" ]; then
        echo "Error: File $file does not exist" >&2
        return 1
    fi
    
    local current_deps
    current_deps=$(get_task_dependencies "$file")
    
    # Check if dependency already exists
    if echo "$current_deps" | grep -q "$new_dep"; then
        return 0  # Already exists, nothing to do
    fi
    
    # Add new dependency
    if [ -n "$current_deps" ]; then
        update_task_dependencies "$file" "$current_deps $new_dep"
    else
        update_task_dependencies "$file" "$new_dep"
    fi
    
    return 0
}

# Remove a dependency from a task  
# Usage: remove_task_dependency "task_file.md" "dependency_id"
# Returns: 0 on success, 1 on failure
remove_task_dependency() {
    local file="$1"
    local dep_to_remove="$2"
    
    if [ ! -f "$file" ]; then
        echo "Error: File $file does not exist" >&2
        return 1
    fi
    
    local current_deps
    current_deps=$(get_task_dependencies "$file")
    
    # Remove the dependency from the list
    local new_deps
    new_deps=$(echo "$current_deps" | sed "s/\\b${dep_to_remove}\\b//g" | tr -s ' ' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    
    update_task_dependencies "$file" "$new_deps"
    
    return 0
}