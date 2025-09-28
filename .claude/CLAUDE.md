# CLAUDE.md

> Think carefully and implement the most concise solution that changes as little code as possible.

## Project-Specific Instructions

Add your project-specific instructions here.

## Testing

Always run tests before committing:
- `npm test` or equivalent for your stack

## Code Style

Follow existing patterns in the codebase.

## Language Configuration

**IMPORTANT:** This project uses a centralized language configuration system.

### Language Rules
Follow the language configuration rules defined in:
- `.claude/rules/language-config.md` - Centralized language preferences and guidelines

### Default Language Behavior
- **Primary Language**: Chinese (中文) - as configured in language rules
- **Fallback Language**: English - for technical terms and when needed
- **Rule Inheritance**: All commands and agents automatically inherit language settings

### Usage
- Commands automatically apply language preferences from global rules
- Agents respond according to configured language settings
- Language switching is available through documentation navigation
- Technical accuracy is preserved across all languages

### Implementation Notes
- Language settings are inherited through this CLAUDE.md file
- No need to specify language in individual commands
- Global configuration ensures consistency across all interactions
- `/re-init` command propagates language updates to this file

For detailed language configuration and usage guidelines, refer to `.claude/rules/language-config.md`.