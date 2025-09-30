#!/bin/bash

# Frontmatter Utility Library
# Provides functions for parsing and updating YAML frontmatter in markdown files

# Get a field value from frontmatter
# Usage: get_frontmatter_field "file.md" "field_name" ["default_value"]
# Returns: field value or default_value (empty string if no default provided)
get_frontmatter_field() {
    local file="$1"
    local field="$2"
    local default="${3:-}"
    
    if [ ! -f "$file" ]; then
        echo "${default}"
        return 1
    fi
    
    # Extract field value, handling various formats
    local value
    value=$(grep "^${field}:" "$file" 2>/dev/null | head -1 | sed "s/^${field}:[[:space:]]*//" | sed 's/[[:space:]]*$//')
    
    if [ -n "$value" ]; then
        echo "$value"
    else
        echo "${default}"
        [ -z "$default" ] && return 1
    fi
}

# Update a field in frontmatter (or add if it doesn't exist)
# Usage: update_frontmatter_field "file.md" "field_name" "new_value"
# Returns: 0 on success, 1 on failure
update_frontmatter_field() {
    local file="$1"
    local field="$2"
    local value="$3"
    
    if [ ! -f "$file" ]; then
        echo "Error: File $file does not exist" >&2
        return 1
    fi
    
    # Check if field exists
    if grep -q "^${field}:" "$file"; then
        # Update existing field (cross-platform sed)
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/^${field}:.*/${field}: ${value}/" "$file"
        else
            sed -i "s/^${field}:.*/${field}: ${value}/" "$file"
        fi
    else
        # Field doesn't exist - add it after the first --- line
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "1,/^---$/s/^---$/${field}: ${value}\n---/" "$file"
        else
            sed -i "1,/^---$/s/^---$/${field}: ${value}\n---/" "$file"
        fi
    fi
    
    return 0
}

# Strip frontmatter from a file and write content to another file
# Usage: strip_frontmatter_to_file "input.md" "output.md"
# Returns: 0 on success, 1 on failure
strip_frontmatter_to_file() {
    local input_file="$1"
    local output_file="$2"
    
    if [ ! -f "$input_file" ]; then
        echo "Error: Input file $input_file does not exist" >&2
        return 1
    fi
    
    # Remove frontmatter (everything between first two --- lines)
    sed '1,/^---$/d; 1,/^---$/d' "$input_file" > "$output_file"
    return 0
}

# Check if file has valid frontmatter with required fields
# Usage: validate_frontmatter "file.md" "field1" "field2" ...
# Returns: 0 if all fields exist, 1 if any missing
validate_frontmatter() {
    local file="$1"
    shift
    local required_fields=("$@")
    
    if [ ! -f "$file" ]; then
        echo "Error: File $file does not exist" >&2
        return 1
    fi
    
    # Check if file has frontmatter at all
    if ! grep -q "^---" "$file"; then
        echo "Error: File $file has no frontmatter" >&2
        return 1
    fi
    
    # Check each required field
    for field in "${required_fields[@]}"; do
        if ! grep -q "^${field}:" "$file"; then
            echo "Error: Missing required field: $field" >&2
            return 1
        fi
    done
    
    return 0
}

# Get all frontmatter fields as key=value pairs
# Usage: get_all_frontmatter "file.md"
# Output: Each line is "field=value"
get_all_frontmatter() {
    local file="$1"
    
    if [ ! -f "$file" ]; then
        return 1
    fi
    
    # Extract frontmatter section and convert to key=value pairs
    awk '
        BEGIN { in_frontmatter=0 }
        /^---$/ { 
            if (in_frontmatter) exit
            in_frontmatter=1; next 
        }
        in_frontmatter && /^[^-]/ && /:/ { 
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
            field = $1
            gsub(/:/, "", field)
            value = substr($0, index($0, ":") + 1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            print field "=" value
        }
    ' "$file"
}

# Add frontmatter to a file that doesn't have it
# Usage: add_frontmatter "file.md" "field1:value1" "field2:value2" ...
# Returns: 0 on success, 1 on failure
add_frontmatter() {
    local file="$1"
    shift
    local fields=("$@")
    
    if [ ! -f "$file" ]; then
        echo "Error: File $file does not exist" >&2
        return 1
    fi
    
    # Check if frontmatter already exists
    if grep -q "^---" "$file"; then
        echo "Error: File $file already has frontmatter" >&2
        return 1
    fi
    
    # Create temporary file with frontmatter
    local temp_file="/tmp/frontmatter_$$"
    echo "---" > "$temp_file"
    for field_value in "${fields[@]}"; do
        echo "$field_value" >> "$temp_file"
    done
    echo "---" >> "$temp_file"
    echo "" >> "$temp_file"
    cat "$file" >> "$temp_file"
    
    # Replace original file
    mv "$temp_file" "$file"
    return 0
}

# Update multiple frontmatter fields at once
# Usage: update_frontmatter_bulk "file.md" "field1:value1" "field2:value2" ...
# Returns: 0 on success, 1 on failure  
update_frontmatter_bulk() {
    local file="$1"
    shift
    local fields=("$@")
    
    if [ ! -f "$file" ]; then
        echo "Error: File $file does not exist" >&2
        return 1
    fi
    
    # Update each field
    for field_value in "${fields[@]}"; do
        local field="${field_value%:*}"
        local value="${field_value#*:}"
        update_frontmatter_field "$file" "$field" "$value"
    done
    
    return 0
}