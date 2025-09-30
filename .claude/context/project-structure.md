---
created: 2025-09-29T06:07:31Z
last_updated: 2025-09-29T06:07:31Z
version: 1.0
author: Claude Code PM System
---

# Project Structure

## Root Directory Organization

```
ccpm/
├── .claude/                    # Claude Code configuration and extensions
├── .git/                       # Git repository metadata
├── ccpm/                       # Core CCPM implementation
├── doc/                        # Additional documentation
├── install/                    # Installation scripts and guides
├── zh-docs/                    # Chinese language documentation
├── AGENTS.md                   # Agent system documentation
├── CHANGELOG.md                # Version history and changes
├── CLAUDE.md                   # Project-specific Claude instructions
├── COMMANDS.md                 # Command reference documentation
├── CONTEXT_ACCURACY.md         # Context system accuracy guidelines
├── LICENSE                     # MIT license file
├── LOCAL_MODE.md               # Local development setup guide
├── README.md                   # Primary project documentation
└── screenshot.webp             # Project showcase image
```

## Core Claude Directory Structure

### `.claude/` - Primary Configuration Hub

```
.claude/
├── CLAUDE.md                   # Base project instructions template
├── agents/                     # Specialized task agents
│   ├── code-analyzer.md        # Code analysis and bug detection
│   ├── file-analyzer.md        # File content analysis and summarization
│   ├── parallel-worker.md      # Multi-stream parallel execution
│   └── test-runner.md          # Test execution and analysis
├── commands/                   # Command implementations
│   ├── context/               # Context management commands
│   │   ├── create.md          # Initialize project context
│   │   ├── prime.md           # Load context for new sessions
│   │   └── update.md          # Refresh existing context
│   └── pm/                    # Project management commands
│       ├── blocked.md         # Show blocked tasks
│       ├── epic-*.md          # Epic management commands
│       ├── help.md            # Command help system
│       ├── in-progress.md     # Active work tracking
│       ├── init.md            # System initialization
│       ├── issue-*.md         # Issue management commands
│       ├── next.md            # Priority task selection
│       ├── prd-*.md           # PRD management commands
│       ├── search.md          # Content search
│       ├── standup.md         # Daily standup reports
│       ├── status.md          # Project dashboard
│       └── validate.md        # System integrity checks
├── context/                    # Project context documentation
│   └── README.md              # Context system overview
├── hooks/                      # Git and workflow hooks
│   └── bash-worktree-fix.sh   # Worktree compatibility fixes
├── rules/                      # Configuration and guidelines
│   └── language-config.md     # Multi-language configuration
└── scripts/                    # Utility and automation scripts
    ├── check-path-standards.sh # Path validation utilities
    ├── fix-path-standards.sh   # Path standardization fixes
    ├── pm/                     # PM system script implementations
    │   ├── blocked.sh          # Blocked task identification
    │   ├── epic-*.sh           # Epic management scripts
    │   ├── help.sh             # Help system
    │   ├── in-progress.sh      # Progress tracking
    │   ├── init.sh             # System setup
    │   ├── next.sh             # Next task logic
    │   ├── prd-*.sh            # PRD processing scripts
    │   ├── search.sh           # Search functionality
    │   ├── standup.sh          # Standup generation
    │   ├── status.sh           # Status reporting
    │   └── validate.sh         # Validation scripts
    └── test-and-log.sh         # Test execution with logging
```

## CCPM Core Implementation

### `ccpm/` - Main System Components

```
ccpm/
├── epics/                      # Epic workspace (gitignored)
│   └── .gitkeep               # Directory placeholder
├── hooks/                      # CCPM-specific hooks
│   └── bash-worktree-fix.sh    # Bash environment fixes
├── lib/                        # Shared libraries
│   └── datetime.sh            # Date/time utilities
└── prds/                       # Product Requirements Documents
    └── .gitkeep               # Directory placeholder
```

## File Naming Conventions

### Documentation Files
- **README.md** - Primary project documentation (English)
- **README_ZH.md** - Chinese language documentation
- **CHANGELOG.md** - Version history and release notes
- **COMMANDS.md** - Comprehensive command reference

### Script Files
- **Pattern**: `{function}.sh` for standalone scripts
- **PM Scripts**: Located in `.claude/scripts/pm/{command}.sh`
- **Utility Scripts**: Located in `.claude/scripts/{utility}.sh`

### Context Files
- **Pattern**: `{category}-{type}.md`
- **Examples**: `project-overview.md`, `tech-context.md`
- **Location**: `.claude/context/`

### Command Files
- **Pattern**: `{command}.md` for command definitions
- **PM Commands**: `.claude/commands/pm/{command}.md`
- **Context Commands**: `.claude/commands/context/{command}.md`

## Directory Responsibilities

### Documentation Directories
- **`doc/`** - Additional documentation and guides
- **`zh-docs/`** - Chinese language documentation mirror
- **`.claude/context/`** - Living project context documentation

### Configuration Directories
- **`.claude/rules/`** - System configuration and guidelines
- **`.claude/hooks/`** - Git and workflow automation hooks

### Executable Directories
- **`.claude/scripts/`** - Automation and utility scripts
- **`install/`** - Installation and setup scripts

### Working Directories
- **`ccpm/epics/`** - Local epic development (excluded from git)
- **`ccpm/prds/`** - Product requirements documents

## Module Organization

### Command System
- **Commands** - Defined in `.claude/commands/{category}/{command}.md`
- **Implementation** - Scripts in `.claude/scripts/{category}/{command}.sh`
- **Documentation** - Usage examples in command definition files

### Agent System
- **Definitions** - Agent capabilities in `.claude/agents/{agent}.md`
- **Specialization** - Each agent handles specific task types
- **Coordination** - Agents work independently but coordinate through git

### Context System
- **Initialization** - Context creation commands
- **Maintenance** - Update and refresh mechanisms
- **Distribution** - Context loading for new sessions

## Integration Points

### Git Integration
- **Worktrees** - Support for parallel development streams
- **Hooks** - Automated workflow triggers
- **Branch Strategy** - Organized development flow

### GitHub Integration
- **Issues** - Primary task and epic tracking
- **Comments** - Progress updates and communication
- **Labels** - Categorization and organization

### Language Support
- **Configuration** - Centralized in `.claude/rules/language-config.md`
- **Documentation** - Parallel documentation structures
- **Navigation** - Cross-language linking system

## Security Considerations

### File Permissions
- **Scripts** - Executable permissions for `.sh` files
- **Documentation** - Read-only for `.md` files
- **Configuration** - Protected configuration files

### Git Exclusions
- **`.gitignore`** - Excludes working directories and sensitive files
- **Local Workspaces** - Epic directories not tracked in repository
- **Temporary Files** - Build artifacts and logs excluded