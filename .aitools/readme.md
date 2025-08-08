# Aider PowerShell Module

This module provides automation tools for PowerShell development in devcontainers, focusing on test maintenance and error handling for PowerShell modules.

## Key Functions

### Invoke-AITool
Core wrapper for AI coding tools (Aider and Claude Code). Used by other functions to interact with AI models for code improvements.

```powershell
# Basic usage
Invoke-AITool -Message "Fix the bug in parameter validation" -File "tests/Get-Something.Tests.ps1"

# Advanced usage with caching and custom model
$params = @{
    Message = "Update parameter tests"
    File = "tests/Update-Database.Tests.ps1"
    Model = "gpt-4o"
    CachePrompts = $true
    AutoTest = $true
}
Invoke-AITool @params
```

### Update-PesterTest
Modernizes Pester tests to v5 format, particularly useful when maintaining legacy test suites.

```powershell
# Update first 10 test files
Update-PesterTest -First 10

# Skip already processed files and update next batch
Update-PesterTest -Skip 10 -First 5 -MaxFileSize 12kb
```

### Repair-Error
Automatically fixes common test errors using AI assistance.

```powershell
# Process all errors from default error file
Repair-Error

# Use custom error file
Repair-Error -ErrorFilePath "custom-errors.json" -First 5
```

### Repair-ParameterTest
Focuses on fixing parameter validation tests.

```powershell
# Fix parameter tests using default settings
Repair-ParameterTest

# Use specific model and limit to first 5 commands
Repair-ParameterTest -First 5 -Model "azure/gpt-4o-mini"
```

## Directory Structure

```
.aider/
├── aider.psm1         # PowerShell module with automation functions
├── prompts/           # AI prompt templates
│   ├── template.md    # Base templates for AI interactions
│   ├── fix-errors.md  # Error fixing prompts
│   └── conventions.md # Coding conventions cache
└── .env              # Environment configuration
```

## Configuration

### .aider.conf.yml
Main configuration file controlling AI behavior, linting, and testing settings. Example:

```yaml
model: azure/gpt-4o-mini
edit_format: whole
auto_lint: true
cache_prompts: true
encoding: utf-8
```

### Environment Variables
Create a `.env` file based on `.env.example` to configure:
- API keys for AI services
- Custom model endpoints
- Project-specific settings

## Best Practices

1. Always use `-CachePrompts` when making multiple similar changes to reduce API costs
2. Set appropriate `-MaxFileSize` limits to prevent processing overly complex files
3. Use `-YesAlways` for batch operations, but review changes in version control
4. Keep prompt templates in `/prompts` directory for consistency
5. Leverage `-ReadFile` for including coding conventions in AI context

## Common Workflows

### Modernizing Test Suite
```powershell
# Step 1: Update to Pester v5
Update-PesterTest -First 1000

# Step 2: Fix any parameter validation issues
Repair-ParameterTest -Model "azure/gpt-4o-mini"

# Step 3: Address remaining errors
Repair-Error
```

### Maintaining Conventions
```powershell
# Update tests with new conventions
$params = @{
    Message = "Update parameter validation style"
    File = "tests/*.Tests.ps1"
    ReadFile = ".aider/prompts/conventions.md"
    CachePrompts = $true
}
Invoke-AITool @params
