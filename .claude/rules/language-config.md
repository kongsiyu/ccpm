# Language Configuration

Centralized language configuration system for CCPM commands and agents.

## Core Language Settings

### Default Language Preference

**Primary Language**: Chinese (中文)
- All output should be in Chinese unless explicitly requested otherwise
- Technical terms may remain in English when Chinese translation would cause confusion
- Error messages and user-facing content should be in Chinese

**Fallback Language**: English
- Use English for technical terms that don't translate well
- Fall back to English if Chinese translation is unclear or unavailable
- Maintain English for code comments and variable names

## Agent Language Instructions

When responding to users:

1. **Default Response Language**: Chinese
   - Use natural, professional Chinese for all explanations
   - Technical concepts should use commonly accepted Chinese terminology
   - Provide clear, concise responses in Chinese

2. **Technical Accuracy**
   - Preserve exact English terms for:
     - Programming keywords (if, else, function, class, etc.)
     - Framework-specific terms that are commonly used in English
     - Command names and file paths
     - Error codes and technical identifiers

3. **Mixed Language Usage**
   - Code examples: Use English for code, Chinese for comments and explanations
   - File paths and commands: Keep in English
   - User interface text: Use Chinese
   - Documentation: Use Chinese with English terms in parentheses when helpful

## Command Output Language

All PM commands should:
- Display status messages in Chinese
- Show help text in Chinese
- Format output with Chinese labels and descriptions
- Keep command names and technical parameters in English

## Examples

### Good Chinese Usage
```
✅ PRD 创建成功: .claude/prds/multi-language.md
📊 项目状态: 0 个 PRD, 0 个 Epic
⚠️ Epic 'multi-language' 已存在。是否覆盖？(yes/no)
```

### Mixed Language for Technical Content
```
正在创建 Issue #1234: 实现用户认证
文件修改: src/auth/login.js, src/components/LoginForm.tsx
状态: in_progress
```

## Implementation Guidelines

### For Commands
- Include this rule reference in command frontmatter: `- .claude/rules/language-config.md`
- Commands automatically inherit these language preferences
- No need to modify individual command logic

### For Agents
- Agents read language preferences from this rule
- Apply language settings consistently across all responses
- Maintain technical accuracy while using Chinese

### For Documentation
- Primary documentation in Chinese (README_ZH.md)
- Technical references can remain bilingual
- User-facing content prioritizes Chinese

## Language Switching

While default is Chinese, users can:
- Explicitly request English responses
- Switch documentation languages via navigation links
- Use English for technical discussions if preferred

## Validation

This configuration ensures:
- Consistent Chinese experience for Chinese users
- Technical accuracy is preserved
- International collaboration remains possible
- Fallback mechanisms prevent communication breakdowns

When implementing language features:
1. Test with Chinese content to ensure proper rendering
2. Verify technical terms are appropriate and understood
3. Ensure fallback to English works smoothly
4. Maintain compatibility with existing English workflows