---
created: 2025-09-29T06:07:31Z
last_updated: 2025-09-29T06:07:31Z
version: 1.0
author: Claude Code PM System
---

# Project Style Guide

## Code Conventions

### Shell Script Standards

#### File Naming
- **Script Files**: Use descriptive names with `.sh` extension
- **Pattern**: `{function-name}.sh` for standalone scripts
- **PM Scripts**: `{command-name}.sh` in `.claude/scripts/pm/`
- **Utility Scripts**: `{utility-name}.sh` in `.claude/scripts/`

#### Script Structure
```bash
#!/bin/bash
# Script description and purpose
# Usage: script-name.sh [arguments]

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Constants and configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(git rev-parse --show-toplevel)"

# Main function
main() {
    # Script logic here
}

# Call main with all arguments
main "$@"
```

#### Error Handling
- **Use `set -euo pipefail`** for robust error handling
- **Validate inputs** before processing
- **Provide clear error messages** with context
- **Exit with appropriate codes**: 0 for success, non-zero for errors

### Documentation Standards

#### Markdown Conventions
- **File Names**: Use kebab-case for filenames (e.g., `project-overview.md`)
- **Headers**: Use sentence case for headers
- **Code Blocks**: Always specify language for syntax highlighting
- **Links**: Use descriptive link text, avoid "click here"

#### YAML Frontmatter
```yaml
---
created: YYYY-MM-DDTHH:MM:SSZ
last_updated: YYYY-MM-DDTHH:MM:SSZ
version: 1.0
author: Claude Code PM System
---
```

#### Section Organization
1. **Overview/Summary** - Brief description of content
2. **Core Content** - Main information organized logically
3. **Examples** - Practical examples where applicable
4. **Related Information** - Links and references

### Command Definition Standards

#### Command Structure
```markdown
# Command Name

Brief description of what the command does.

## Required Rules

**IMPORTANT:** Before executing this command, read and follow:
- `.claude/rules/example.md` - Specific requirements

## Instructions

Detailed step-by-step instructions.

## Examples

```bash
/command:example arg1 arg2
```

## Important Notes

- Critical information
- Limitations or constraints
```

#### Parameter Documentation
- **Required Parameters**: Clearly marked as required
- **Optional Parameters**: Default values specified
- **Parameter Types**: String, number, boolean clearly indicated
- **Validation Rules**: Input validation requirements

## File Organization Standards

### Directory Structure
```
.claude/
├── agents/           # Agent definitions (alphabetical)
├── commands/         # Command definitions (by category)
│   ├── context/     # Context management commands
│   └── pm/          # Project management commands
├── context/          # Project context (by type)
├── rules/           # Configuration and guidelines
└── scripts/         # Implementation scripts (by category)
    └── pm/          # PM system scripts
```

### File Naming Conventions
- **Commands**: `{command-name}.md`
- **Scripts**: `{command-name}.sh`
- **Context**: `{context-type}.md`
- **Agents**: `{agent-name}.md`
- **Rules**: `{rule-topic}.md`

### Git Exclusions
```gitignore
# Working directories
ccpm/epics/
.claude/epics/

# Temporary files
*.tmp
*.log
.DS_Store
```

## Language and Localization

### Primary Language Support
- **Default Language**: Chinese (中文) as configured in language rules
- **Fallback Language**: English for technical terms and when needed
- **Configuration**: Centralized in `.claude/rules/language-config.md`

### Documentation Patterns
- **Parallel Structures**: Maintain equivalent documentation in both languages
- **Cross-Language Navigation**: Bidirectional linking between language versions
- **Technical Consistency**: Use consistent technical terms across languages
- **Cultural Adaptation**: Adapt examples and references for target culture

### Command Response Patterns
- **Language Inheritance**: Commands automatically apply language preferences
- **Technical Accuracy**: Preserve technical accuracy across languages
- **User Experience**: Consistent experience regardless of language choice
- **Error Messages**: Clear error messages in user's preferred language

## Quality Standards

### Code Quality
- **Readability**: Code should be self-documenting with clear variable names
- **Modularity**: Break complex functions into smaller, focused functions
- **Reusability**: Create reusable functions in shared libraries
- **Testing**: Include validation and error handling for all scripts

### Documentation Quality
- **Clarity**: Information should be clear and unambiguous
- **Completeness**: Cover all necessary information for task completion
- **Currency**: Keep documentation updated with changes
- **Examples**: Include practical examples for complex concepts

### Consistency Standards
- **Terminology**: Use consistent terms throughout all documentation
- **Formatting**: Apply consistent formatting across all files
- **Structure**: Follow established patterns for similar content types
- **Style**: Maintain consistent tone and voice

## Command Implementation Standards

### Script Implementation
```bash
#!/bin/bash
# Command: pm:example
# Description: Example command implementation
# Usage: pm:example [options] <required-arg>

set -euo pipefail

# Source common utilities
source "$(dirname "$0")/../../lib/common.sh"

# Command-specific functions
validate_arguments() {
    if [[ $# -lt 1 ]]; then
        echo "Error: Missing required argument"
        echo "Usage: pm:example <required-arg>"
        exit 1
    fi
}

main() {
    validate_arguments "$@"

    # Command logic here
    echo "Executing example command with: $1"
}

main "$@"
```

### Error Handling Patterns
- **Input Validation**: Validate all inputs before processing
- **Graceful Degradation**: Provide fallback behavior when possible
- **Clear Messages**: Error messages should be actionable
- **Exit Codes**: Use standard exit codes (0=success, 1=error, 2=usage error)

## Agent Definition Standards

### Agent Structure
```markdown
# Agent Name

Brief description of agent capabilities.

## Agent Capabilities

- **Primary Function**: Main purpose of the agent
- **Specialized Skills**: Specific expertise areas
- **Tool Access**: Tools available to the agent

## Usage Patterns

When to use this agent and typical workflows.

## Important Notes

- Configuration requirements
- Limitations or constraints
```

### Agent Coordination
- **Independence**: Agents should work independently when possible
- **Coordination**: Use git commits for coordination when needed
- **Context Sharing**: Share context through documented files
- **Conflict Resolution**: Clear patterns for resolving conflicts

## Testing and Validation

### Script Testing
- **Unit Tests**: Test individual functions where possible
- **Integration Tests**: Test complete command workflows
- **Error Scenarios**: Test error handling and edge cases
- **Performance**: Monitor execution time for optimization

### Documentation Validation
- **Link Checking**: Verify all links are functional
- **Example Testing**: Ensure all examples work as documented
- **Completeness**: Verify all features are documented
- **Accuracy**: Keep documentation synchronized with implementation

## Maintenance Standards

### Version Control
- **Commit Messages**: Use conventional commit format
- **Branch Strategy**: Feature branches for new development
- **Change Documentation**: Update CHANGELOG.md for significant changes
- **Tagging**: Use semantic versioning for releases

### Regular Maintenance
- **Documentation Updates**: Keep documentation current with changes
- **Dependency Updates**: Monitor and update dependencies
- **Performance Review**: Regular performance assessment
- **Security Review**: Regular security assessment and updates

## Best Practices

### Development Workflow
1. **Plan**: Document requirements and approach
2. **Implement**: Follow coding standards and patterns
3. **Test**: Validate functionality and error handling
4. **Document**: Update documentation and examples
5. **Review**: Code review before merging

### Collaboration
- **Clear Communication**: Use descriptive commit messages and PR descriptions
- **Knowledge Sharing**: Document decisions and rationale
- **Consistent Style**: Follow established patterns and conventions
- **Feedback Integration**: Incorporate feedback constructively

### Continuous Improvement
- **Pattern Recognition**: Identify and document recurring patterns
- **Automation**: Automate repetitive tasks where possible
- **Optimization**: Continuously improve performance and usability
- **Community Feedback**: Incorporate user feedback and suggestions