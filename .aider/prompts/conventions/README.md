# dbatools Testing Conventions

This directory contains organized testing conventions for the dbatools project, with individual files for easy reference and maintenance.

**Note**: Content has been migrated and organized from the original `.aider/prompts/conventions.md` file into focused category files for better maintainability and reference.

## Convention Files

### 📄 Headers
- [`header.md`](header.md) - Required header conventions

### 🏗️ Structure
- [`structure.md`](structure.md) - Describe block structure conventions

### 🎨 Formatting
- [`formatting.md`](formatting.md) - Code style formatting conventions

### 🏷️ Naming
- [`naming.md`](naming.md) - Test naming conventions

### 🧪 Testing
- [`testing.md`](testing.md) - Testing best practices conventions

### 🧹 Cleanup
- [`cleanup.md`](cleanup.md) - Cleanup formatting rules conventions

### ⚙️ Syntax
- [`syntax.md`](syntax.md) - PowerShell syntax conventions

## Usage Guide

### For Update-PesterTests Function

When referencing these conventions in the `Update-PesterTests` function, use the following pattern:

```powershell
# Reference specific convention files
$HeaderConventions = Get-Content ".aider/prompts/conventions/header.md" -Raw
$StructureConventions = Get-Content ".aider/prompts/conventions/structure.md" -Raw
$FormattingConventions = Get-Content ".aider/prompts/conventions/formatting.md" -Raw
$NamingConventions = Get-Content ".aider/prompts/conventions/naming.md" -Raw
$TestingConventions = Get-Content ".aider/prompts/conventions/testing.md" -Raw
$CleanupConventions = Get-Content ".aider/prompts/conventions/cleanup.md" -Raw
$SyntaxConventions = Get-Content ".aider/prompts/conventions/syntax.md" -Raw
```

### Convention Categories

Each category serves a specific purpose:

- **Headers**: Standard file headers, metadata, and documentation requirements
- **Structure**: Test organization, describe blocks, and logical grouping
- **Formatting**: Code style, indentation, and visual presentation
- **Naming**: Consistent naming patterns for tests, variables, and functions
- **Testing**: Best practices for writing effective tests
- **Cleanup**: Post-test cleanup and resource management
- **Syntax**: PowerShell-specific syntax rules and patterns

## Maintenance

- Each `.md` file should contain focused, actionable guidelines
- Update conventions based on project evolution and community feedback
- Maintain consistency across all convention files
- Keep examples current and relevant to the dbatools project

## Migration Notes

The content in these files has been extracted and organized from the original comprehensive conventions file to provide:
- Better organization and maintainability
- Easier reference for specific convention types
- Focused content for each aspect of testing standards
- Simplified updates to individual convention categories

### Original Source
Content was migrated from `.aider/prompts/conventions.md` which contained comprehensive Pester v5 test standards for the dbatools module.