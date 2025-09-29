#!/bin/bash

# DateTime Utility Library
# Provides cross-platform functions for handling ISO timestamps and date operations

# Get current timestamp in ISO 8601 format (UTC)
# Usage: get_current_iso_timestamp
# Returns: Current time in format "2023-12-25T10:30:45Z"
get_current_iso_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Convert ISO timestamp to Unix timestamp (seconds since epoch)
# Usage: iso_to_timestamp "2023-12-25T10:30:45Z"
# Returns: Unix timestamp or "0" on error
iso_to_timestamp() {
    local iso_date="$1"
    
    if [ -z "$iso_date" ]; then
        echo "0"
        return 1
    fi
    
    # Try GNU date format first (Linux)
    local timestamp
    timestamp=$(date -d "$iso_date" "+%s" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$timestamp" ]; then
        echo "$timestamp"
        return 0
    fi
    
    # Try macOS date format
    timestamp=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso_date" "+%s" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$timestamp" ]; then
        echo "$timestamp"
        return 0
    fi
    
    # Fallback: try without timezone suffix
    local clean_date
    clean_date=$(echo "$iso_date" | sed 's/Z$//')
    
    # Try GNU date with cleaned input
    timestamp=$(date -d "${clean_date}Z" "+%s" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$timestamp" ]; then
        echo "$timestamp"
        return 0
    fi
    
    # Try macOS date with cleaned input
    timestamp=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$clean_date" "+%s" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$timestamp" ]; then
        echo "$timestamp"
        return 0
    fi
    
    echo "0"
    return 1
}

# Convert Unix timestamp to ISO format
# Usage: timestamp_to_iso "1703505045"
# Returns: ISO timestamp or empty on error
timestamp_to_iso() {
    local timestamp="$1"
    
    if [ -z "$timestamp" ] || [ "$timestamp" = "0" ]; then
        echo ""
        return 1
    fi
    
    # Try GNU date format first
    local iso_date
    iso_date=$(date -u -d "@$timestamp" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$iso_date" ]; then
        echo "$iso_date"
        return 0
    fi
    
    # Try macOS date format
    iso_date=$(date -u -r "$timestamp" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$iso_date" ]; then
        echo "$iso_date"
        return 0
    fi
    
    echo ""
    return 1
}

# Compare two ISO timestamps and return which is newer
# Usage: compare_iso_timestamps "2023-01-01T10:00:00Z" "2023-01-02T10:00:00Z"  
# Returns: "first" if first is newer, "second" if second is newer, "equal" if same
# Exit code: 0 if comparison successful, 1 on error
compare_iso_timestamps() {
    local first_iso="$1"
    local second_iso="$2"
    
    if [ -z "$first_iso" ] || [ -z "$second_iso" ]; then
        echo "error"
        return 1
    fi
    
    local first_ts
    local second_ts
    
    first_ts=$(iso_to_timestamp "$first_iso")
    second_ts=$(iso_to_timestamp "$second_iso")
    
    if [ "$first_ts" = "0" ] || [ "$second_ts" = "0" ]; then
        echo "error"
        return 1
    fi
    
    if [ "$first_ts" -gt "$second_ts" ]; then
        echo "first"
    elif [ "$first_ts" -lt "$second_ts" ]; then
        echo "second"
    else
        echo "equal"
    fi
    
    return 0
}

# Check if first timestamp is newer than second
# Usage: is_timestamp_newer "2023-01-02T10:00:00Z" "2023-01-01T10:00:00Z"
# Returns: 0 (true) if first is newer, 1 (false) otherwise
is_timestamp_newer() {
    local first_iso="$1"
    local second_iso="$2"
    
    local result
    result=$(compare_iso_timestamps "$first_iso" "$second_iso")
    
    [ "$result" = "first" ]
}

# Get relative time description (e.g., "3 days ago", "2 hours ago")
# Usage: get_relative_time "2023-12-20T10:00:00Z"
# Returns: Human-readable relative time or "unknown" on error
get_relative_time() {
    local iso_date="$1"
    
    if [ -z "$iso_date" ]; then
        echo "unknown"
        return 1
    fi
    
    local target_ts
    local current_ts
    
    target_ts=$(iso_to_timestamp "$iso_date")
    current_ts=$(iso_to_timestamp "$(get_current_iso_timestamp)")
    
    if [ "$target_ts" = "0" ] || [ "$current_ts" = "0" ]; then
        echo "unknown"
        return 1
    fi
    
    local diff=$((current_ts - target_ts))
    
    # Handle future dates
    if [ $diff -lt 0 ]; then
        diff=$((-diff))
        local suffix="from now"
    else
        local suffix="ago"
    fi
    
    # Convert to appropriate units
    if [ $diff -lt 60 ]; then
        echo "${diff} seconds $suffix"
    elif [ $diff -lt 3600 ]; then
        local minutes=$((diff / 60))
        echo "${minutes} minute$([ $minutes -ne 1 ] && echo "s") $suffix"
    elif [ $diff -lt 86400 ]; then
        local hours=$((diff / 3600))
        echo "${hours} hour$([ $hours -ne 1 ] && echo "s") $suffix"
    elif [ $diff -lt 2592000 ]; then
        local days=$((diff / 86400))
        echo "${days} day$([ $days -ne 1 ] && echo "s") $suffix"
    elif [ $diff -lt 31536000 ]; then
        local months=$((diff / 2592000))
        echo "${months} month$([ $months -ne 1 ] && echo "s") $suffix"
    else
        local years=$((diff / 31536000))
        echo "${years} year$([ $years -ne 1 ] && echo "s") $suffix"
    fi
}

# Get age of file in days based on ISO timestamp in frontmatter
# Usage: get_file_age_days "task.md" "updated"
# Returns: Number of days since timestamp, or -1 on error
get_file_age_days() {
    local file="$1"
    local timestamp_field="${2:-updated}"
    
    if [ ! -f "$file" ]; then
        echo "-1"
        return 1
    fi
    
    # Source frontmatter library if not already loaded
    if ! type get_frontmatter_field >/dev/null 2>&1; then
        local script_dir="$(dirname "${BASH_SOURCE[0]}")"
        source "$script_dir/frontmatter.sh"
    fi
    
    local file_timestamp
    file_timestamp=$(get_frontmatter_field "$file" "$timestamp_field")
    
    if [ -z "$file_timestamp" ]; then
        echo "-1"
        return 1
    fi
    
    local file_ts
    local current_ts
    
    file_ts=$(iso_to_timestamp "$file_timestamp")
    current_ts=$(iso_to_timestamp "$(get_current_iso_timestamp)")
    
    if [ "$file_ts" = "0" ] || [ "$current_ts" = "0" ]; then
        echo "-1"
        return 1
    fi
    
    local diff_days=$(((current_ts - file_ts) / 86400))
    echo "$diff_days"
}

# Check if a file is older than specified number of days
# Usage: is_file_older_than_days "task.md" 30 "updated"
# Returns: 0 (true) if older, 1 (false) if newer or on error
is_file_older_than_days() {
    local file="$1"
    local max_days="$2"
    local timestamp_field="${3:-updated}"
    
    local age_days
    age_days=$(get_file_age_days "$file" "$timestamp_field")
    
    if [ "$age_days" -eq -1 ]; then
        return 1
    fi
    
    [ "$age_days" -gt "$max_days" ]
}

# Format timestamp for human display
# Usage: format_timestamp_display "2023-12-25T10:30:45Z"
# Returns: "Dec 25, 2023 10:30 UTC" or original string on error
format_timestamp_display() {
    local iso_date="$1"
    
    if [ -z "$iso_date" ]; then
        echo ""
        return 1
    fi
    
    local timestamp
    timestamp=$(iso_to_timestamp "$iso_date")
    
    if [ "$timestamp" = "0" ]; then
        echo "$iso_date"  # Return original if can't parse
        return 1
    fi
    
    # Try to format in a readable way (cross-platform)
    local formatted
    
    # GNU date
    formatted=$(date -u -d "@$timestamp" "+%b %d, %Y %H:%M UTC" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$formatted" ]; then
        echo "$formatted"
        return 0
    fi
    
    # macOS date  
    formatted=$(date -u -r "$timestamp" "+%b %d, %Y %H:%M UTC" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$formatted" ]; then
        echo "$formatted"
        return 0
    fi
    
    # Fallback to original
    echo "$iso_date"
    return 1
}