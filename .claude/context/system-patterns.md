---
created: 2025-09-29T06:07:31Z
last_updated: 2025-09-29T06:07:31Z
version: 1.0
author: Claude Code PM System
---

# System Patterns and Architecture

## Core Architectural Patterns

### Command Pattern Implementation
**Pattern**: Separation of command definition from execution
**Implementation**:
- **Command Definitions**: `.claude/commands/{category}/{command}.md`
- **Command Implementations**: `.claude/scripts/{category}/{command}.sh`
- **Command Invocation**: Slash command syntax (`/pm:command`)

**Benefits**:
- Clean separation of concerns
- Easy command documentation and maintenance
- Extensible command system

### Agent-Based Architecture
**Pattern**: Specialized autonomous agents for domain-specific tasks
**Implementation**:
- **Agent Definitions**: `.claude/agents/{agent-name}.md`
- **Agent Specialization**: Domain-specific capabilities (testing, analysis, file processing)
- **Agent Coordination**: Git-based coordination without direct communication

**Benefits**:
- Parallel execution capability
- Context optimization through specialization
- Scalable task distribution

### Context Management Pattern
**Pattern**: Persistent project knowledge across sessions
**Implementation**:
- **Context Storage**: `.claude/context/` directory
- **Context Initialization**: `/context:create` command
- **Context Loading**: `/context:prime` command
- **Context Updates**: `/context:update` command

**Benefits**:
- Knowledge persistence across sessions
- Faster agent onboarding
- Consistent project understanding

## Data Flow Patterns

### Hierarchical Task Flow
**Pattern**: PRD → Epic → Tasks → Issues → Code
**Implementation**:
```
PRD Creation (/pm:prd-new)
    ↓
Epic Planning (/pm:prd-parse)
    ↓
Task Decomposition (/pm:epic-decompose)
    ↓
GitHub Sync (/pm:epic-sync)
    ↓
Parallel Execution (/pm:issue-start)
```

**Benefits**:
- Full traceability from requirements to code
- Structured development process
- Parallel task execution capability

### Bidirectional Synchronization
**Pattern**: Local-first development with GitHub synchronization
**Implementation**:
- **Local Work**: All planning and execution happens locally
- **Sync Points**: Explicit synchronization with GitHub
- **Conflict Resolution**: GitHub as source of truth for shared state

**Benefits**:
- Fast local operations
- Controlled collaboration
- Conflict-free parallel development

## State Management Patterns

### File-Based State Storage
**Pattern**: State persisted in structured markdown files
**Implementation**:
- **PRDs**: `.claude/prds/{name}.md`
- **Epics**: `.claude/epics/{name}/epic.md`
- **Tasks**: `.claude/epics/{name}/{task-id}.md`
- **Context**: `.claude/context/{context-type}.md`

**Benefits**:
- Human-readable state
- Version control integration
- Easy backup and migration

### Frontmatter Metadata Pattern
**Pattern**: YAML frontmatter for structured metadata
**Implementation**:
```yaml
---
created: 2025-09-29T06:07:31Z
last_updated: 2025-09-29T06:07:31Z
version: 1.0
status: in_progress
---
```

**Benefits**:
- Structured metadata within documents
- Automated processing capability
- Human and machine readable

## Execution Patterns

### Parallel Agent Execution
**Pattern**: Multiple agents working simultaneously on related tasks
**Implementation**:
- **Issue Decomposition**: Single issues split into parallel work streams
- **Git Worktrees**: Isolated working directories for each agent
- **Coordination**: Git commits for coordination between agents

**Benefits**:
- Significantly faster development
- Context optimization
- Reduced blocking dependencies

### Incremental Synchronization
**Pattern**: Local work with periodic synchronization
**Implementation**:
- **Local Development**: All work happens locally first
- **Batch Updates**: Periodic sync with GitHub
- **Progress Tracking**: GitHub comments for progress visibility

**Benefits**:
- Fast iteration cycles
- Controlled external communication
- Progress transparency

## Error Handling Patterns

### Graceful Degradation
**Pattern**: System continues to function with reduced capabilities
**Implementation**:
- **GitHub CLI Missing**: Fall back to manual issue creation
- **Extension Missing**: Fall back to simple task lists
- **Network Issues**: Continue local work, sync later

**Benefits**:
- System resilience
- Continued productivity
- User experience consistency

### Validation and Recovery
**Pattern**: Proactive validation with automated recovery
**Implementation**:
- **System Validation**: `/pm:validate` command
- **Path Standardization**: Automated path fixing
- **Integrity Checks**: Automated consistency verification

**Benefits**:
- Early problem detection
- Automated problem resolution
- System reliability

## Integration Patterns

### GitHub-Native Integration
**Pattern**: Use GitHub as the external collaboration interface
**Implementation**:
- **Issues**: Primary task tracking
- **Comments**: Progress updates and communication
- **Labels**: Organization and categorization
- **Projects**: Optional visualization layer

**Benefits**:
- Team collaboration
- Tool integration
- Audit trail
- Standard workflows

### Language-Agnostic Design
**Pattern**: System works regardless of project programming language
**Implementation**:
- **Shell Scripts**: Universal automation layer
- **Markdown**: Universal documentation format
- **Git**: Universal version control
- **GitHub**: Universal collaboration platform

**Benefits**:
- Project type independence
- Wide applicability
- Consistent experience across technologies

## Configuration Patterns

### Centralized Configuration
**Pattern**: Single source of truth for system configuration
**Implementation**:
- **Language Config**: `.claude/rules/language-config.md`
- **Project Instructions**: `CLAUDE.md`
- **Agent Definitions**: `.claude/agents/`

**Benefits**:
- Consistent behavior
- Easy maintenance
- Clear documentation

### Inheritance Pattern
**Pattern**: Configuration inheritance from global to local
**Implementation**:
- **Global Rules**: `.claude/rules/`
- **Project Instructions**: `CLAUDE.md`
- **Local Overrides**: Command-specific parameters

**Benefits**:
- Configuration reuse
- Flexible customization
- Maintainable hierarchy

## Quality Patterns

### Spec-Driven Development
**Pattern**: "No Vibe Coding" - every code change traces to specification
**Implementation**:
1. **Brainstorm** - Deep thinking about requirements
2. **Document** - Detailed specifications
3. **Plan** - Technical architecture decisions
4. **Execute** - Implementation according to spec
5. **Track** - Progress monitoring and updates

**Benefits**:
- High code quality
- Reduced bugs
- Clear requirements
- Full traceability

### Continuous Context Updates
**Pattern**: Living documentation that evolves with project
**Implementation**:
- **Context Creation**: Initial comprehensive context
- **Context Updates**: Regular refresh of project state
- **Context Priming**: Loading context for new sessions

**Benefits**:
- Current project knowledge
- Reduced onboarding time
- Consistent understanding

## Performance Patterns

### Context Optimization
**Pattern**: Minimal context loading for maximum performance
**Implementation**:
- **Specialized Agents**: Focused context per agent
- **Lazy Loading**: Load context only when needed
- **Context Isolation**: Agent contexts don't pollute main conversation

**Benefits**:
- Faster execution
- Lower token usage
- Better focus
- Scalable performance

### Batch Operations
**Pattern**: Group related operations for efficiency
**Implementation**:
- **Batch GitHub Sync**: Multiple issues created together
- **Parallel Tool Calls**: Multiple bash commands in single message
- **Grouped Updates**: Multiple file operations batched

**Benefits**:
- Reduced API calls
- Faster execution
- Better resource utilization
- Improved user experience