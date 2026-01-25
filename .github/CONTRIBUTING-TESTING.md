# Running dbatools Tests Locally - A Complete Tutorial

This tutorial explains how to run dbatools tests locally against your SQL Server lab. It covers the test infrastructure, configuration, and best practices based on recent improvements by Andreas Jordan.

---

## Table of Contents

1. [Overview: What Changed](#overview-what-changed)
2. [Prerequisites](#prerequisites)
3. [Step 1: Install Dependencies](#step-1-install-dependencies)
4. [Step 2: Configure Your SQL Instances](#step-2-configure-your-sql-instances)
5. [Step 3: Test Your Configuration](#step-3-test-your-configuration)
6. [Step 4: Run Tests](#step-4-run-tests)
7. [Understanding Test Scenarios](#understanding-test-scenarios)
8. [CI/CD Integration](#cicd-integration)
9. [Troubleshooting](#troubleshooting)

---

## Overview: What Changed

We recently refactored the test suite to use **scenario-based testing**. Instead of generic `instance1`, `instance2`, `instance3` naming, tests now use purpose-specific instance references:

| Old Pattern | New Pattern | Purpose |
|-------------|-------------|---------|
| `$TestConfig.instance1` | `$TestConfig.InstanceSingle` | Tests needing one instance |
| `$TestConfig.instance1/2` | `$TestConfig.InstanceMulti1/2` | Tests needing multiple instances |
| - | `$TestConfig.InstanceCopy1/2` | Tests that copy between instances |
| - | `$TestConfig.InstanceHadr` | HA/DR tests (AGs, mirroring, log shipping) |
| - | `$TestConfig.InstanceRestart` | Tests that restart SQL Server |

**Why this matters:** The CI/CD can now run tests in parallel based on infrastructure requirements, and your local tests can use the same pattern.

---

## Prerequisites

Before starting, ensure you have:

- **PowerShell 5.1+** (Windows PowerShell) or **PowerShell 7+** (recommended)
- **Git** for cloning the repository
- **At least one SQL Server instance** for basic tests
- **Two SQL Server instances** for most integration tests
- **Administrator access** to your SQL instances

### IMPORTANT: Run PowerShell as Administrator

Many dbatools commands require local Administrator privileges to function correctly. Commands like:

- `Copy-DbaLinkedServer`
- `Copy-DbaLogin` (when migrating Windows logins)
- `Get-DbaService`
- `Restart-DbaService`
- Any command that accesses WMI, Windows services, or performs cross-server operations

**Recommendation:** Always run your PowerShell session as Administrator when testing dbatools. This prevents cryptic permission errors and ensures all tests can run.

```powershell
# To verify you're running as Administrator:
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "You are NOT running as Administrator. Many dbatools tests will fail."
} else {
    Write-Host "Running as Administrator - Good!" -ForegroundColor Green
}
```

---

## Step 1: Install Dependencies

Open PowerShell as Administrator and navigate to your dbatools repository:

```powershell
cd c:\github\dbatools
```

### 1.1 Install dbatools.library (REQUIRED)

The `dbatools.library` module contains the SMO assemblies. Without it, nothing works.

```powershell
# Run the install script
.\.github\scripts\install-dbatools-library.ps1
```

This script:
- Reads the required version from `.github/dbatools-library-version.json`
- Installs from PowerShell Gallery or GitHub releases
- Works cross-platform

### 1.2 Install Pester (Testing Framework)

```powershell
Install-Module Pester -RequiredVersion 5.7.1 -Force -SkipPublisherCheck
```

### 1.3 Install PSScriptAnalyzer (Code Formatting)

```powershell
Install-Module PSScriptAnalyzer -RequiredVersion 1.18.2 -Force
```

### 1.4 Import dbatools

```powershell
# Import from source
Import-Module .\dbatools.psd1 -Force
```

---

## Step 2: Configure Your SQL Instances

### 2.1 Create Your Local Configuration File

Copy the example file:

```powershell
Copy-Item .\tests\constants.local.ps1.example .\tests\constants.local.ps1
```

### 2.2 Edit constants.local.ps1

Open `tests\constants.local.ps1` and configure it for your lab. Here's a complete example:

```powershell
# constants.local.ps1 - Configure for your SQL Server lab

# ============================================
# SQL Server Instance Configuration
# ============================================

# For tests that need a single instance
$config['InstanceSingle'] = "YourServer\Instance1"

# For tests that need multiple instances (comparisons, migrations)
$config['InstanceMulti1'] = "YourServer\Instance1"
$config['InstanceMulti2'] = "YourServer\Instance2"

# For tests that copy data between instances
$config['InstanceCopy1'] = "YourServer\Instance1"
$config['InstanceCopy2'] = "YourServer\Instance2"

# For HA/DR tests (Availability Groups, Mirroring, Log Shipping)
# Set this if you have AG-enabled instances
$config['InstanceHadr'] = "YourServer\Instance2"

# For tests that restart SQL Server (use with caution!)
$config['InstanceRestart'] = "YourServer\Instance2"

# Legacy support - some older tests still use these
$config['instance1'] = $config['InstanceSingle']
$config['instance2'] = $config['InstanceMulti2']

# ============================================
# Authentication
# ============================================

# Option 1: SQL Authentication (recommended for testing)
$securePassword = ConvertTo-SecureString "YourStrongPassword!" -AsPlainText -Force
$config['SqlCred'] = New-Object System.Management.Automation.PSCredential ("sa", $securePassword)

# Option 2: Windows Authentication (leave SqlCred as $null)
# $config['SqlCred'] = $null

# Set default credential for all dbatools commands
$config['Defaults']['*:SqlCredential'] = $config['SqlCred']
$config['Defaults']['*:SourceSqlCredential'] = $config['SqlCred']
$config['Defaults']['*:DestinationSqlCredential'] = $config['SqlCred']

# ============================================
# Test Infrastructure
# ============================================

# Computer name for certain tests
$config['dbatoolsci_computer'] = $env:COMPUTERNAME

# Temp directory for test files
# IMPORTANT: For remote instances, use a network share accessible by both
# the SQL Server service account AND your PowerShell session
$config['Temp'] = "C:\Temp"
# Example for remote: $config['Temp'] = "\\FileServer\Share\dbatools-tests"
```

### 2.3 Configuration Tips for Your Lab

**If you have one SQL Server:**
```powershell
# Point everything to your single instance
$config['InstanceSingle'] = "localhost\SQL2019"
$config['InstanceMulti1'] = "localhost\SQL2019"
$config['InstanceMulti2'] = "localhost\SQL2019"  # Same instance - some tests will skip
$config['InstanceCopy1'] = "localhost\SQL2019"
$config['InstanceCopy2'] = "localhost\SQL2019"
```

**If you have two SQL Servers:**
```powershell
$config['InstanceSingle'] = "Server1\SQL2019"
$config['InstanceMulti1'] = "Server1\SQL2019"
$config['InstanceMulti2'] = "Server2\SQL2022"
$config['InstanceCopy1'] = "Server1\SQL2019"
$config['InstanceCopy2'] = "Server2\SQL2022"
```

**If you have remote instances:**
```powershell
# Critical: Use a shared temp path!
$config['Temp'] = "\\FileServer\DBAtoolsTests"
```

**If you have a mix of local and remote instances:**

This is the most flexible but requires careful temp path configuration:

```powershell
# ============================================
# MIXED LOCAL + REMOTE CONFIGURATION
# ============================================

# Local instance for quick single-instance tests
$config['InstanceSingle'] = "localhost\SQL2019"

# Use local + remote for multi-instance tests
$config['InstanceMulti1'] = "localhost\SQL2019"
$config['InstanceMulti2'] = "RemoteServer\SQL2022"

# Copy tests REQUIRE both instances to access the same temp path
# Create a network share on your local machine or use a file server
$config['InstanceCopy1'] = "localhost\SQL2019"
$config['InstanceCopy2'] = "RemoteServer\SQL2022"

# HADR typically needs dedicated instances with specific config
$config['InstanceHadr'] = "RemoteServer\SQL2022"

# Restart tests - use an instance you can safely restart
$config['InstanceRestart'] = "RemoteServer\SQL2022"

# ============================================
# CRITICAL: TEMP PATH FOR MIXED ENVIRONMENTS
# ============================================
# The temp path must be accessible from:
# 1. Your PowerShell session (to write test files)
# 2. ALL SQL Server instances (for backup/restore operations)

# Option A: Create a share on your local machine
# Create folder: C:\Temp\dbatools-tests
# Share it as: \\YourWorkstation\dbatools-tests
# Grant read/write to: SQL Server service accounts from all servers
$config['Temp'] = "\\$env:COMPUTERNAME\dbatools-tests"

# Option B: Use an existing file server share
$config['Temp'] = "\\FileServer\Share\dbatools-tests"

# Option C: For tests that don't cross instances, use local path
# WARNING: Backup/restore tests between instances will fail!
# $config['Temp'] = "C:\Temp"
```

**Setting up the network share (required for cross-instance tests):**

```powershell
# Run as Administrator on your workstation
$sharePath = "C:\Temp\dbatools-tests"
New-Item -Path $sharePath -ItemType Directory -Force

# Create share with Everyone having full access (adjust for your security needs)
New-SmbShare -Name "dbatools-tests" -Path $sharePath -FullAccess "Everyone"

# Verify the share works from your remote SQL Server
# On the remote server, test: Test-Path "\\YourWorkstation\dbatools-tests"
```

---

## Step 3: Test Your Configuration

### 3.1 Load the Module and Configuration

```powershell
# Start fresh
Remove-Module dbatools -ErrorAction SilentlyContinue

# Import the module
Import-Module .\dbatools.psd1 -Force
Import-Module .\dbatools.psm1 -Force  # For internal functions

# Get the test configuration
$TestConfig = Get-TestConfig

# Set default credentials
$PSDefaultParameterValues["*:SqlCredential"] = $TestConfig.SqlCred
```

### 3.2 Verify Your Instances

```powershell
# Test connectivity to your instances
$TestConfig.InstanceSingle | Connect-DbaInstance | Select-Object Name, Version
$TestConfig.InstanceMulti1 | Connect-DbaInstance | Select-Object Name, Version
$TestConfig.InstanceMulti2 | Connect-DbaInstance | Select-Object Name, Version
```

### 3.3 Trust Certificates (If Needed)

If you see certificate errors:

```powershell
Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Register
Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $false -Register
```

---

## Step 4: Run Tests

### Method 1: Invoke-ManualPester (Recommended)

The `Invoke-ManualPester` function is a helper designed for local testing:

```powershell
# Run unit tests only (no SQL Server required)
Invoke-ManualPester -Path Get-DbaDatabase

# Run integration tests (requires SQL Server)
Invoke-ManualPester -Path Get-DbaDatabase -TestIntegration

# Run with code coverage
Invoke-ManualPester -Path Get-DbaDatabase -TestIntegration -Coverage

# Run with full coverage including dependencies
Invoke-ManualPester -Path Get-DbaDatabase -TestIntegration -Coverage -DependencyCoverage

# Run with script analyzer check
Invoke-ManualPester -Path Get-DbaDatabase -TestIntegration -ScriptAnalyzer

# Run multiple tests matching a pattern
Invoke-ManualPester -Path "*Backup*" -TestIntegration

# Show less output
Invoke-ManualPester -Path Get-DbaDatabase -TestIntegration -Show None
```

### Method 2: Direct Pester Invocation

```powershell
# First, set up the environment
Import-Module .\dbatools.psd1 -Force
Import-Module .\dbatools.psm1 -Force
$TestConfig = Get-TestConfig
$PSDefaultParameterValues = $TestConfig.Defaults

# Run a specific test file
Invoke-Pester .\tests\Get-DbaDatabase.Tests.ps1 -Output Detailed

# Run only unit tests
Invoke-Pester .\tests\Get-DbaDatabase.Tests.ps1 -Output Detailed -Tag UnitTests

# Run only integration tests
Invoke-Pester .\tests\Get-DbaDatabase.Tests.ps1 -Output Detailed -Tag IntegrationTests

# Run multiple test files
Invoke-Pester .\tests\*Backup*.Tests.ps1 -Output Detailed
```

### Method 3: Quick Manual Test

For quickly verifying a command works:

```powershell
# Setup
Import-Module .\dbatools.psm1 -Force
$TestConfig = Get-TestConfig
$PSDefaultParameterValues["*:SqlCredential"] = $TestConfig.SqlCred

# Now manually test commands
Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle | Select-Object -First 5
```

---

## Understanding Test Scenarios

Tests are organized into scenarios based on infrastructure requirements. This is defined in `tests\pester.groups.ps1`:

| Scenario | Description | Test Detection |
|----------|-------------|----------------|
| **SINGLE** | Tests needing one instance | Files containing `$TestConfig.InstanceSingle` |
| **MULTI** | Tests needing multiple instances | Files containing `$TestConfig.InstanceMulti` |
| **COPY** | Tests that copy between instances | Files containing `$TestConfig.InstanceCopy` |
| **HADR** | HA/DR tests (AGs, mirroring) | Files containing `$TestConfig.InstanceHadr` |
| **RESTART** | Tests that restart SQL Server | Files containing `$TestConfig.InstanceRestart` |

### Running Scenario-Specific Tests

```powershell
# The CI sets $env:SCENARIO, but you can test locally:
$env:SCENARIO = "SINGLE"
# Then run tests - they'll be filtered to SINGLE scenario

# Or manually filter
Get-ChildItem .\tests\*.Tests.ps1 | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    if ($content -match '\$TestConfig\.InstanceSingle' -and
        $content -notmatch '\$TestConfig\.InstanceMulti') {
        # This is a SINGLE scenario test
        $_.Name
    }
}
```

---

## CI/CD Integration

### Commit Message Magic

Control which tests run in CI using commit message patterns:

```bash
# Run only Get-DbaDatabase tests
git commit -m "Fix database enumeration (do Get-DbaDatabase)"

# Run all backup-related tests
git commit -m "Update backup logic (do *Backup*)"

# Run multiple specific tests
git commit -m "Fix login handling (do Get-DbaLogin, Set-DbaLogin)"

# Skip CI entirely
git commit -m "Update comments [skip ci]"
```

### AppVeyor Build Matrix

The CI runs tests across multiple scenarios in parallel:

```yaml
# From appveyor.yml
matrix:
  - scenario: SINGLE (split into 3 parts for speed)
  - scenario: MULTI
  - scenario: COPY
  - scenario: HADR
  - scenario: RESTART
```

---

## Troubleshooting

### "dbatools.library not found"

```powershell
# Reinstall it
.\.github\scripts\install-dbatools-library.ps1 -Force

# Check it's installed
Get-Module -ListAvailable dbatools.library
```

### "Cannot connect to SQL Server"

```powershell
# Check the instance name
$TestConfig.InstanceSingle  # Make sure this is correct

# Test raw connectivity
Test-DbaConnection -SqlInstance $TestConfig.InstanceSingle

# If using SQL auth, verify credentials
$TestConfig.SqlCred.UserName  # Should show "sa" or your username
```

### "Access denied to temp path"

For remote instances, the SQL Server service account needs write access to `$config['Temp']`:

```powershell
# Use a network share
$config['Temp'] = "\\FileServer\Share\dbatools-tests"

# Ensure the share has write permissions for:
# - Your user account (running PowerShell)
# - SQL Server service accounts (for backup/restore tests)
```

### "Test failed: EnableException"

Tests use `EnableException` in `BeforeAll` and `AfterAll` blocks to catch setup failures:

```powershell
# If you see EnableException errors, the test setup failed
# Check if your instances are accessible
# Check if you have permissions to create databases, etc.
```

### "Access denied" or "permission" errors

Many dbatools commands require local Administrator privileges:

```powershell
# Check if running as admin
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host "Running as Admin: $isAdmin"

# If not admin, restart PowerShell as Administrator
# Commands that commonly need admin:
# - Copy-DbaLinkedServer, Copy-DbaLogin (Windows logins)
# - Get-DbaService, Restart-DbaService, Stop-DbaService
# - Get-DbaComputerSystem, Get-DbaOperatingSystem
# - Any WMI-based operations
```

### "Tests hang or timeout"

Some tests create databases, backups, or other resources. If a previous test failed:

```powershell
# Clean up leftover test databases
Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -ExcludeSystem |
    Where-Object Name -like "dbatoolsci_*" |
    Remove-DbaDatabase -Confirm:$false

# Clean up temp files
Get-ChildItem $TestConfig.Temp -Recurse |
    Where-Object Name -like "*dbatoolsci*" |
    Remove-Item -Recurse -Force
```

---

## Quick Reference

```powershell
# === IMPORTANT: RUN POWERSHELL AS ADMINISTRATOR ===
# Many commands (Copy-DbaLinkedServer, Get-DbaService, etc.) require admin rights

# === INITIAL SETUP (one time) ===
.\.github\scripts\install-dbatools-library.ps1
Install-Module Pester -RequiredVersion 5.7.1 -Force -SkipPublisherCheck
Install-Module PSScriptAnalyzer -RequiredVersion 1.18.2 -Force
Copy-Item .\tests\constants.local.ps1.example .\tests\constants.local.ps1
# Edit constants.local.ps1 with your instances

# === BEFORE EACH TEST SESSION ===
Import-Module .\dbatools.psd1 -Force
Import-Module .\dbatools.psm1 -Force
$TestConfig = Get-TestConfig
$PSDefaultParameterValues["*:SqlCredential"] = $TestConfig.SqlCred

# === RUN TESTS ===
# Easy way
Invoke-ManualPester -Path Get-DbaDatabase -TestIntegration

# Direct Pester
Invoke-Pester .\tests\Get-DbaDatabase.Tests.ps1 -Output Detailed

# Run all tests for a pattern
Invoke-ManualPester -Path "*Backup*" -TestIntegration
```

---

## Files Referenced

| File | Purpose |
|------|---------|
| [tests/constants.local.ps1.example](../tests/constants.local.ps1.example) | Template for local config |
| [private/testing/Get-TestConfig.ps1](../private/testing/Get-TestConfig.ps1) | Loads test configuration |
| [private/testing/Invoke-ManualPester.ps1](../private/testing/Invoke-ManualPester.ps1) | Local test runner helper |
| [tests/pester.groups.ps1](../tests/pester.groups.ps1) | Scenario definitions |
| [tests/appveyor.common.ps1](../tests/appveyor.common.ps1) | CI test discovery logic |
| [tests/CLAUDE.md](../tests/CLAUDE.md) | Pester v5 test standards |
