# dbatools.library Version Management

This document describes the centralized version management system for dbatools.library dependencies in the dbatools project.

## Overview

The dbatools.library version management system provides a centralized approach to managing dbatools.library versions across all CI/CD pipelines and development environments. Instead of hardcoding versions in multiple workflow files, the system uses a single JSON configuration file that all workflows reference dynamically.

**Key Benefits:**
- **Single Source of Truth**: One file controls the version across all environments
- **Easy Updates**: Change version in one place to update everywhere
- **Preview Support**: Seamlessly use preview/development versions
- **Fallback Strategy**: Automatic fallback from PowerShell Gallery to GitHub releases
- **Consistency**: Ensures all workflows use the same version
- **Cross-Platform**: Works on Windows, Linux, and macOS

## Architecture

### Core Components

#### 1. JSON Configuration File (`.github/dbatools-library-version.json`)

The central configuration file that defines the dbatools.library version:

```json
{
  "version": "2024.4.12",
  "notes": "Version of dbatools.library to use for CI/CD and development"
}
```

**Fields:**
- `version`: The dbatools.library version to use (supports both release and preview versions)
- `notes`: Human-readable description of the configuration purpose

#### 2. Install Script (`.github/scripts/install-dbatools-library.ps1`)

A comprehensive PowerShell script that handles the installation logic with intelligent fallback:

```powershell
# Example usage - reads from default JSON config
.\.github\scripts\install-dbatools-library.ps1

# Example usage with parameters
.\.github\scripts\install-dbatools-library.ps1 -Force -Scope AllUsers
```

**Key Features:**
- **PowerShell Gallery First**: Attempts installation from PowerShell Gallery
- **GitHub Releases Fallback**: Falls back to GitHub releases if Gallery fails
- **Preview Version Support**: Handles both stable and preview versions
- **Cross-Platform**: Works on Windows, Linux, and macOS
- **Error Handling**: Comprehensive error reporting and retry logic
- **Verbose Logging**: Detailed output with timestamps and color coding
- **Module Verification**: Confirms successful installation

**Parameters:**
- `ConfigPath`: Path to JSON config file (defaults to relative path)
- `Force`: Forces reinstallation even if module exists
- `Scope`: Installation scope - 'CurrentUser' (default) or 'AllUsers'

#### 3. GitHub Workflows Integration

All workflows dynamically read the version from the JSON file using this pattern:

```yaml
- name: Read dbatools.library version
  id: get-version
  shell: pwsh
  run: |
    $versionConfig = Get-Content '.github/dbatools-library-version.json' | ConvertFrom-Json
    $version = $versionConfig.version
    Write-Output "version=$version" >> $env:GITHUB_OUTPUT
    Write-Output "Using dbatools.library version: $version"

- name: Install and cache PowerShell modules
  uses: potatoqualitee/psmodulecache@v6.2.1
  with:
    modules-to-cache: dbatools.library:${{ steps.get-version.outputs.version }}
```

## Usage Instructions

### Updating the Version

To update the dbatools.library version across all workflows:

1. **Edit the JSON file**:
   ```json
   {
     "version": "2025.8.1",
     "notes": "Updated to stable release 2025.8.1"
   }
   ```

2. **Commit and push**:
   ```bash
   git add .github/dbatools-library-version.json
   git commit -m "Update dbatools.library to version 2025.8.1"
   git push
   ```

3. **Verify**: All subsequent workflow runs will use the new version automatically.

### Using Preview Versions

Preview versions follow the pattern: `YYYY.M.D-preview-branch-YYYYMMDD.HHMMSS`

**Example preview version**: `2025.7.12-preview-main-20250712.175548`

To use a preview version:

```json
{
  "version": "2025.7.12-preview-main-20250712.175548",
  "notes": "Using preview build for testing new features"
}
```

### PowerShell Gallery → GitHub Releases Fallback

The install script implements a two-tier approach:

1. **Primary**: Attempts installation from PowerShell Gallery
   ```powershell
   Install-Module dbatools.library -RequiredVersion $Version -Scope CurrentUser -Force
   ```

2. **Fallback**: If Gallery fails, downloads from GitHub releases
   ```powershell
   # Downloads from: https://github.com/dataplat/dbatools.library/releases/download/v{version}/dbatools.library.zip
   ```

**When fallback triggers:**
- Version not available on PowerShell Gallery (common for previews)
- PowerShell Gallery connectivity issues
- Authentication/permission problems with Gallery
- Network timeouts or service disruptions

**Fallback Process:**
1. Downloads release ZIP from GitHub
2. Extracts to temporary directory
3. Installs to appropriate PowerShell module path based on scope
4. Verifies installation success
5. Cleans up temporary files

## CI/CD Integration

### GitHub Actions Workflows

All GitHub Actions workflows follow this consistent pattern. Currently integrated workflows:

- **[`xplat-import.yml`](.workflows/xplat-import.yml)**: Cross-platform import testing on Ubuntu, Windows, and macOS
- **[`integration-tests.yml`](.workflows/integration-tests.yml)**: Full integration test suite with Docker containers
- **[`gallery.yml`](.workflows/gallery.yml)**: PowerShell Gallery version testing

**Standard Workflow Pattern:**
```yaml
name: Example Workflow
on: [push]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3

    - name: Read dbatools.library version
      id: get-version
      shell: pwsh
      run: |
        $versionConfig = Get-Content '.github/dbatools-library-version.json' | ConvertFrom-Json
        $version = $versionConfig.version
        Write-Output "version=$version" >> $env:GITHUB_OUTPUT
        Write-Output "Using dbatools.library version: $version"

    - name: Install and cache PowerShell modules
      uses: potatoqualitee/psmodulecache@v6.2.1
      with:
        modules-to-cache: dbatools.library:${{ steps.get-version.outputs.version }}

    - name: Your workflow steps
      shell: pwsh
      run: |
        Import-Module ./dbatools.psd1 -Force
        # Your commands here
```

### AppVeyor Integration

AppVeyor automatically uses the version defined in [`dbatools.psd1`](dbatools.psd1):

```powershell
# From dbatools.psd1 - AppVeyor reads this automatically
ModuleVersion = '2.1.32'
```

**AppVeyor Behavior:**
- Reads `ModuleVersion` from `dbatools.psd1` manifest
- Uses its own dependency resolution mechanism
- No additional configuration needed
- Independent of the GitHub JSON configuration
- Maintains backward compatibility with existing setup

## Developer Guide

### Local Testing

Test the install script locally before committing changes:

```powershell
# Test with current JSON config version
.\.github\scripts\install-dbatools-library.ps1

# Test with force reinstall
.\.github\scripts\install-dbatools-library.ps1 -Force

# Test with AllUsers scope (requires admin)
.\.github\scripts\install-dbatools-library.ps1 -Scope AllUsers

# Test with custom config path
.\.github\scripts\install-dbatools-library.ps1 -ConfigPath "path\to\custom\config.json"
```

### Command Examples

#### 1. **Standard Release Version**
```json
{
  "version": "2025.8.1",
  "notes": "Updated to stable release 2025.8.1 for production use"
}
```

#### 2. **Preview Version Testing**
```json
{
  "version": "2025.8.1-preview-feature-20250801.120000",
  "notes": "Testing preview build with new SMO compatibility features"
}
```

#### 3. **Emergency Rollback**
```json
{
  "version": "2025.7.1",
  "notes": "Emergency rollback due to compatibility issues in 2025.8.1"
}
```

#### 4. **Development Branch Testing**
```json
{
  "version": "2025.8.1-preview-dev-20250801.150000",
  "notes": "Testing development branch features before merge"
}
```

### Local Development Testing

```powershell
# Step 1: Test the install script locally
PS> .\.github\scripts\install-dbatools-library.ps1 -Force

# Step 2: Verify installation
PS> Get-Module dbatools.library -ListAvailable | Select-Object Name, Version, Path

# Step 3: Test dbatools import
PS> Import-Module .\dbatools.psd1 -Force

# Step 4: Verify dbatools.library is loaded correctly
PS> (Get-Module dbatools.library).Version

# Step 5: Test basic functionality
PS> Get-DbaManagementObject
```

### Troubleshooting

#### Common Issues

1. **Version Not Found on PowerShell Gallery**
   ```
   Failed to install from PowerShell Gallery: Package 'dbatools.library' with version 'X.X.X' not found
   ```
   **Solution**: Script automatically falls back to GitHub releases. This is expected for preview versions.

2. **GitHub Release Download Failure**
   ```
   Failed to install from GitHub releases: The remote server returned an error: (404) Not Found
   ```
   **Solution**: Verify the version exists in [GitHub releases](https://github.com/dataplat/dbatools.library/releases).

3. **Permission Issues (AllUsers scope)**
   ```
   Access denied: Administrator rights required for AllUsers scope
   ```
   **Solution**: Run PowerShell as Administrator or use `-Scope CurrentUser`.

4. **Module Already Exists Warning**
   ```
   dbatools.library version X.X.X is already installed. Use -Force to reinstall.
   ```
   **Solution**: Use `-Force` parameter to reinstall, or this is normal behavior.

#### Debug Commands

```powershell
# Check available versions on PowerShell Gallery
Find-Module dbatools.library -AllVersions | Select-Object Name, Version

# Verify current installation
Get-Module dbatools.library -ListAvailable | Format-Table Name, Version, Path

# Test JSON config parsing
$config = Get-Content '.github/dbatools-library-version.json' | ConvertFrom-Json
Write-Host "Current configured version: $($config.version)"

# Check module loading in dbatools
Import-Module .\dbatools.psd1 -Force -Verbose

# Verify SMO functionality
(Get-DbaManagementObject).LoadTemplate -ne $null
```

#### Platform-Specific Issues

**Linux/macOS:**
```powershell
# Check PowerShell module paths
$env:PSModulePath -split [System.IO.Path]::PathSeparator

# Verify permissions on module directory
ls -la ~/.local/share/powershell/Modules/
```

**Windows:**
```powershell
# Check PowerShell module paths (PowerShell Core)
$env:PSModulePath -split ';'

# Check Windows PowerShell module paths
$env:PSModulePath -split ';' | Where-Object { $_ -like "*WindowsPowerShell*" }
```

## Migration Notes

### What Changed

#### Before (Hardcoded Approach)
```yaml
# Old approach - hardcoded in each workflow
- name: Install dbatools.library
  run: Install-Module dbatools.library -RequiredVersion "2024.3.1" -Force
```

- Versions scattered across multiple workflow files
- Manual updates required in each file
- Risk of inconsistent versions between workflows
- Difficult to maintain and track changes
- No fallback mechanism for unavailable versions

#### After (Centralized System)
```yaml
# New approach - dynamic from JSON config
- name: Read dbatools.library version
  id: get-version
  run: |
    $config = Get-Content '.github/dbatools-library-version.json' | ConvertFrom-Json
    echo "version=$($config.version)" >> $env:GITHUB_OUTPUT

- name: Install and cache PowerShell modules
  uses: potatoqualitee/psmodulecache@v6.2.1
  with:
    modules-to-cache: dbatools.library:${{ steps.get-version.outputs.version }}
```

- Single JSON file controls all versions
- Automatic propagation to all workflows
- Guaranteed version consistency
- Intelligent fallback mechanism
- Better error handling and logging

### Benefits of New System

1. **Maintainability**: Single point of update reduces human error
2. **Consistency**: All environments guaranteed to use identical versions
3. **Flexibility**: Easy switching between stable/preview versions
4. **Reliability**: Fallback mechanism ensures high availability
5. **Transparency**: Clear versioning history in git commits
6. **Automation**: No manual workflow file updates needed
7. **Testing**: Easy to test different versions locally
8. **Rollback**: Quick version rollbacks in emergencies

### Migration Timeline

**Phase 1 - Infrastructure** ✅
- Created centralized JSON configuration
- Developed intelligent install script with fallback
- Added comprehensive error handling and logging

**Phase 2 - Workflow Integration** ✅
- Updated [`xplat-import.yml`](.workflows/xplat-import.yml)
- Updated [`integration-tests.yml`](.workflows/integration-tests.yml)
- Updated [`gallery.yml`](.workflows/gallery.yml)

**Phase 3 - Compatibility** ✅
- Maintained AppVeyor compatibility with `dbatools.psd1`
- Ensured no breaking changes to existing functionality
- Added preview version support

### Backward Compatibility

- **AppVeyor**: Continues using `ModuleVersion` from `dbatools.psd1` (no changes required)
- **Existing Workflows**: Remain functional during transition period
- **Manual Installations**: Direct `Install-Module` commands still work as fallback
- **Local Development**: No impact on developer workflows

## Best Practices

### Version Management
- **Semantic Versioning**: Use semantic versioning for releases (`YYYY.M.D`)
- **Descriptive Commits**: Use clear commit messages when updating versions
- **Testing**: Test preview versions in non-production environments first
- **Documentation**: Document significant version changes in pull request descriptions
- **Rollback Plan**: Keep previous working version noted for quick rollbacks

### Workflow Integration
- **Consistency**: Always use the centralized version system for new workflows
- **Error Handling**: Include comprehensive error handling for version read operations
- **Logging**: Add verbose logging for troubleshooting workflow issues
- **Testing**: Test workflows with both stable and preview versions
- **Caching**: Use module caching to improve workflow performance

### Development Workflow
1. **Update**: Modify version in JSON configuration file
2. **Test Locally**: Run install script locally to verify
3. **Commit**: Commit changes with descriptive message
4. **Monitor**: Watch workflow runs for successful version adoption
5. **Verify**: Confirm all dependent systems update correctly
6. **Document**: Update this documentation if process changes

### Security Considerations
- **Scope**: Use `CurrentUser` scope by default to avoid privilege escalation
- **Verification**: Always verify module installation after download
- **Cleanup**: Ensure temporary files are cleaned up after installation
- **Source Validation**: Both PowerShell Gallery and GitHub releases are trusted sources

---

## Support and Troubleshooting

For questions or issues with the version management system:

1. **Issues**: Create an issue in the [dbatools repository](https://github.com/dbatools/dbatools/issues)
2. **Discussions**: Use [GitHub Discussions](https://github.com/dbatools/dbatools/discussions) for questions
3. **Library Issues**: Report dbatools.library specific issues in the [dbatools.library repository](https://github.com/dataplat/dbatools.library/issues)
4. **Community**: Join the [dbatools Slack community](https://dbatools.io/slack) for real-time help

**When reporting issues, please include:**
- The version you're trying to install
- Your operating system and PowerShell version
- The complete error message
- Whether you're using the script directly or through a workflow