---
created: 2025-09-29T06:07:31Z
last_updated: 2025-09-29T06:07:31Z
version: 1.0
author: Claude Code PM System
---

# Technology Context

## Primary Technology Stack

### Core Technologies
- **Shell Scripting** - Bash for automation and system integration
- **Markdown** - Documentation and configuration format
- **Git** - Version control and workflow foundation
- **GitHub CLI** - API integration and issue management

### Development Environment
- **Platform**: Cross-platform (Windows, macOS, Linux)
- **Shell**: Bash-compatible environments
- **Dependencies**: Minimal external requirements

## System Dependencies

### Required Dependencies
1. **Git** (v2.0+)
   - Core version control functionality
   - Worktree support for parallel development
   - Branch management and merging

2. **GitHub CLI** (gh)
   - Issue creation and management
   - Authentication handling
   - API access for repository operations

3. **gh-sub-issue Extension**
   - Parent-child issue relationships
   - Hierarchical task organization
   - Epic-to-task linking

### Optional Dependencies
1. **Node.js** - For JavaScript/TypeScript projects
2. **Python** - For Python-based projects
3. **Docker** - For containerized applications
4. **Various Language Tools** - Project-specific requirements

## Architecture Patterns

### Command Pattern
- **Structure**: Commands defined in `.claude/commands/`
- **Implementation**: Scripts in `.claude/scripts/`
- **Separation**: Clean separation between definition and execution

### Agent Pattern
- **Specialization**: Domain-specific agents for different tasks
- **Autonomy**: Agents operate independently with context
- **Coordination**: Git-based coordination mechanism

### Context Pattern
- **Persistence**: Project state maintained across sessions
- **Initialization**: Automated context creation
- **Updates**: Incremental context refreshing

## File Formats and Standards

### Documentation Format
- **Primary**: GitHub Flavored Markdown
- **Structure**: YAML frontmatter for metadata
- **Conventions**: Consistent heading hierarchy and formatting

### Configuration Format
- **Language Config**: YAML-based language preferences
- **Command Definitions**: Markdown with embedded YAML
- **Script Parameters**: Environment variable based

### Data Exchange
- **GitHub Issues**: JSON via GitHub CLI
- **Local Storage**: Markdown files with frontmatter
- **Script Communication**: Environment variables and file system

## Development Tools

### Code Quality
- **Shell Linting**: ShellCheck for bash script validation
- **Markdown Linting**: markdownlint for documentation consistency
- **Path Standards**: Custom validation scripts

### Testing Framework
- **Test Runner**: Custom test execution with logging
- **Agent Testing**: Specialized test-runner agent
- **Integration Tests**: GitHub API interaction validation

### Automation
- **Git Hooks**: Workflow automation triggers
- **Script Utilities**: Reusable bash functions
- **Path Standardization**: Automated path validation and fixing

## Integration Technologies

### GitHub Integration
- **API Access**: GitHub REST API via GitHub CLI
- **Authentication**: OAuth token-based authentication
- **Rate Limiting**: Built-in respect for API limits

### Git Workflow
- **Worktrees**: Parallel development support
- **Branch Strategy**: Feature branches with merge coordination
- **Commit Standards**: Conventional commit messages

### Cross-Platform Support
- **Windows**: PowerShell and WSL compatibility
- **macOS**: Native bash and Homebrew integration
- **Linux**: Standard bash environment support

## Performance Considerations

### Scalability
- **Parallel Execution**: Multiple agents working simultaneously
- **Context Optimization**: Minimal context loading overhead
- **File System**: Efficient local file operations

### Resource Usage
- **Memory**: Minimal memory footprint
- **Network**: Efficient GitHub API usage
- **Storage**: Local file-based storage system

### Optimization Strategies
- **Caching**: Local context caching
- **Lazy Loading**: On-demand context loading
- **Batch Operations**: Grouped GitHub API calls

## Security Framework

### Authentication
- **GitHub**: OAuth token-based authentication
- **Local Storage**: Secure token storage via GitHub CLI
- **API Access**: Scoped permissions for repository access

### Data Protection
- **Sensitive Data**: No sensitive data in repository
- **Local Files**: Temporary files excluded from git
- **API Tokens**: Managed by GitHub CLI securely

### Access Control
- **Repository Access**: Standard GitHub permissions
- **Command Execution**: User-controlled script execution
- **File Permissions**: Standard file system permissions

## Language and Internationalization

### Multi-Language Support
- **Primary Language**: Chinese (中文) as configured
- **Fallback Language**: English for technical terms
- **Configuration**: Centralized in `.claude/rules/language-config.md`

### Localization Features
- **Documentation**: Parallel documentation trees
- **Commands**: Language-aware command responses
- **Navigation**: Cross-language documentation linking

## Version Management

### Release Strategy
- **Upstream Sync**: Regular synchronization with automazeio/ccpm
- **Fork Maintenance**: Local enhancements while maintaining compatibility
- **Version Tracking**: Git tags and changelog maintenance

### Compatibility
- **Backward Compatibility**: Maintained across versions
- **API Stability**: Stable command interface
- **Migration Support**: Automated upgrade paths

## Monitoring and Logging

### Execution Logging
- **Test Execution**: Comprehensive test logging
- **Command Tracing**: Debug-level command execution tracking
- **Error Handling**: Structured error reporting

### Performance Monitoring
- **Command Timing**: Execution time tracking
- **Resource Usage**: Memory and CPU monitoring
- **API Usage**: GitHub API call tracking

## Future Technology Considerations

### Planned Enhancements
- **Enhanced Testing**: Expanded test coverage
- **Performance Optimization**: Script execution optimization
- **Additional Language Support**: Framework ready for expansion

### Technology Evolution
- **GitHub API**: Adaptation to API changes
- **Shell Evolution**: Compatibility with shell updates
- **Integration Expansion**: Additional tool integrations