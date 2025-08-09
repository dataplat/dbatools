# dbatools AI Tools Module

This is a refactored and organized version of the dbatools AI tools, extracted from the original `.aitools/pr.psm1` and `.aitools/aitools.psm1` files.

## Module Structure

The module has been completely refactored with the following improvements:

### ✅ Completed Refactoring Tasks

1. **Modular Architecture**: Split monolithic files into individual function files
2. **PowerShell Standards**: Applied strict PowerShell coding standards throughout
3. **Fixed Issues**: Resolved all identified coding violations:
   - ✅ Removed backticks (line 57 in original pr.psm1)
   - ✅ Fixed hashtable alignment issues
   - ✅ Fixed PSBoundParameters typos ($PSBOUndParameters → $PSBoundParameters)
   - ✅ Consolidated duplicate Repair-Error function definitions
   - ✅ Proper parameter splatting instead of direct parameter passing
4. **Clean Organization**: Separated major commands from helper functions
5. **Module Manifest**: Created proper PowerShell module with manifest

### File Organization

```
module/
├── aitools.psd1          # Module manifest
├── aitools.psm1          # Main module file
├── README.md                      # This documentation
│
├── Major Commands (8 files):
├── Repair-PullRequestTest.ps1     # Main PR test repair function
├── Show-AppVeyorBuildStatus.ps1   # AppVeyor status display
├── Get-AppVeyorFailures.ps1       # AppVeyor failure retrieval
├── Update-PesterTest.ps1          # Pester v5 migration
├── Invoke-AITool.ps1              # AI tool interface
├── Invoke-AutoFix.ps1             # PSScriptAnalyzer auto-fix
├── Repair-Error.ps1               # Error repair (consolidated)
├── Repair-SmallThing.ps1          # Small issue repairs
│
└── Helper Functions (12 files):
    ├── Invoke-AppVeyorApi.ps1         # AppVeyor API wrapper
    ├── Get-AppVeyorFailure.ps1        # Failure extraction
    ├── Repair-TestFile.ps1            # Individual test repair
    ├── Get-TargetPRs.ps1              # PR number resolution
    ├── Get-FailedBuilds.ps1           # Failed build detection
    ├── Get-BuildFailures.ps1          # Build failure analysis
    ├── Get-JobFailures.ps1            # Job failure extraction
    ├── Get-TestArtifacts.ps1          # Test artifact retrieval
    ├── Parse-TestArtifact.ps1         # Artifact parsing
    ├── Format-TestFailures.ps1        # Failure formatting
    ├── Invoke-AutoFixSingleFile.ps1   # Single file AutoFix
    └── Invoke-AutoFixProcess.ps1      # AutoFix core logic
```

## Installation

```powershell
# Import the module
Import-Module ./module/aitools.psd1

# Verify installation
Get-Command -Module aitools
```

## Available Functions

### Major Commands

| Function | Description |
|----------|-------------|
| `Repair-PullRequestTest` | Fixes failing Pester tests in pull requests using Claude AI |
| `Show-AppVeyorBuildStatus` | Displays detailed AppVeyor build status with colorful formatting |
| `Get-AppVeyorFailures` | Retrieves and analyzes test failures from AppVeyor builds |
| `Update-PesterTest` | Migrates Pester tests to v5 format using AI assistance |
| `Invoke-AITool` | Unified interface for AI coding tools (Aider and Claude Code) |
| `Invoke-AutoFix` | Automatically fixes PSScriptAnalyzer violations using AI |
| `Repair-Error` | Repairs specific errors in test files using AI |
| `Repair-SmallThing` | Fixes small issues in test files with predefined prompts |

### Helper Functions

All helper functions are automatically imported but not exported publicly. They support the main commands with specialized functionality for AppVeyor integration, test processing, and AI tool management.

## Requirements

- PowerShell 5.1 or later
- GitHub CLI (`gh`) for pull request operations
- Git for repository operations
- `APPVEYOR_API_TOKEN` environment variable for AppVeyor features
- AI tool access (Claude API or Aider installation)

## Usage Examples

```powershell
# Fix failing tests in all open PRs
Repair-PullRequestTest

# Fix tests in a specific PR with auto-commit
Repair-PullRequestTest -PRNumber 1234 -AutoCommit

# Show AppVeyor build status
Show-AppVeyorBuildStatus -BuildId 12345

# Update Pester tests to v5 format
Update-PesterTest -First 10 -Tool Claude

# Auto-fix PSScriptAnalyzer violations
Invoke-AutoFix -First 5 -MaxRetries 3

# Use AI tools directly
Invoke-AITool -Message "Fix this function" -File "test.ps1" -Tool Claude
```

## Key Improvements

### Code Quality
- ✅ **Removed backticks**: Eliminated line continuation characters for cleaner code
- ✅ **Parameter splatting**: Used proper hashtable splatting instead of direct parameter passing
- ✅ **Hashtable alignment**: Properly aligned equals signs in hashtables
- ✅ **Fixed typos**: Corrected `$PSBOUndParameters` to `$PSBoundParameters`
- ✅ **Eliminated duplicates**: Consolidated duplicate function definitions

### Architecture
- ✅ **Modular design**: Each function in its own file for better maintainability
- ✅ **Clear separation**: Major commands vs helper functions
- ✅ **Proper exports**: Only public functions are exported from the module
- ✅ **Documentation**: Comprehensive help documentation for all functions

### Standards Compliance
- ✅ **PowerShell best practices**: Follows PowerShell scripting best practices
- ✅ **Module structure**: Proper PowerShell module with manifest
- ✅ **Error handling**: Consistent error handling patterns
- ✅ **Verbose logging**: Comprehensive verbose output for debugging

## Migration from Original Files

The original files have been completely refactored:

- **`.aitools/pr.psm1`** (1048 lines) → Split into 8 major commands + 12 helper functions
- **`.aitools/aitools.psm1`** (2012 lines) → Integrated and refactored into the new structure

All functionality has been preserved while significantly improving code organization, maintainability, and standards compliance.

## Testing

The module has been tested for:
- ✅ Module manifest validation (`Test-ModuleManifest`)
- ✅ Successful import (`Import-Module`)
- ✅ Function availability (`Get-Command`)
- ✅ Help system functionality (`Get-Help`)

## Support

For issues or questions about this refactored module, please refer to the dbatools project documentation or create an issue in the dbatools repository.