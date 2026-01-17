# dbatools

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/dbatools)](https://www.powershellgallery.com/packages/dbatools)
[![Downloads](https://img.shields.io/powershellgallery/dt/dbatools)](https://www.powershellgallery.com/packages/dbatools)
[![Build Status](https://img.shields.io/github/actions/workflow/status/dataplat/dbatools/integration-tests.yml?branch=development)](https://github.com/dataplat/dbatools/actions)
[![GitHub Stars](https://img.shields.io/github/stars/dataplat/dbatools?style=social)](https://github.com/dataplat/dbatools)

<img align="left" src="https://raw.githubusercontent.com/dataplat/dbatools/development/bin/dbatools.png" alt="dbatools logo">

**Migrate SQL Server instances in minutes instead of days.** Test hundreds of backups automatically. Find that one database across 50 servers. dbatools is a PowerShell module with nearly 700 commands that replace manual SQL Server administration with powerful and fun automation.

**Performance at Scale:** Migrate terabyte databases in under an hour. Test 1000+ backups per hour. Manage 100+ SQL instances from a single console.

## Table of Contents
- [Why dbatools?](#why-dbatools)
- [Quick Start](#quick-start)
- [System Requirements](#system-requirements)
- [Common Use Cases](#common-use-cases)
- [Installation](#installation)
- [Getting Help](#getting-help)
- [Advanced Usage](#advanced-usage)
- [Troubleshooting](#troubleshooting)
- [Community & Support](#community--support)
- [Contributing](#contributing)

## Why dbatools?

| Traditional Methods | dbatools |
|-------------------|----------|
| **SSMS:** Click through 50 servers manually | **PowerShell:** Query all 50 servers in one command |
| **Migration:** Days of planning and execution | **Migration:** Minutes with automated best practices |
| **Backup Testing:** Manual restores, hope for the best | **Backup Testing:** Automated verification of all backups |
| **Documentation:** Hours of manual collection | **Documentation:** Instant HTML/Excel reports |
| **Scripting:** Complex T-SQL across versions | **Scripting:** Consistent commands for SQL 2000-2022 |

## Quick Start

```powershell
# Check your PowerShell version (v3+ required for Windows, Core 7.4+ for Linux/macOS)
$PSVersionTable.PSVersion

# Install (Windows/Linux/macOS)
Install-Module dbatools -Scope CurrentUser

# See your databases
Get-DbaDatabase -SqlInstance localhost

# Check your backups
Get-DbaLastBackup -SqlInstance localhost | Format-Table

# Test your last backup (yes, really!)
Test-DbaLastBackup -SqlInstance localhost
```

## System Requirements

### SQL Server Support
| Version | Commands Supported |
|---------|-------------------|
| SQL Server 2000 | 75% |
| SQL Server 2005 | 90% |
| SQL Server 2008/R2 | 93% |
| SQL Server 2012+ | 100% |
| Azure SQL VM | As per version above |
| Azure SQL Database | 40% |
| Azure SQL Managed Instance | 60% |
| Containers/Kubernetes | 75% |

### Operating System Support
| OS | Commands Supported | PowerShell Required |
|----|-------------------|-------------------|
| Windows 7/8/10/11 | 100% | v3+ |
| Windows Server 2008 R2+ | 100% | v3+ |
| Linux (Intel/ARM64) | 78% | Core 7.4.0+ |
| macOS (Intel/M1) | 78% | Core 7.4.0+ |

💡 **Note:** Commands requiring SQL WMI or `-ComputerName` parameter typically don't work on Linux/macOS.

### Network Requirements
For remote SQL Server management, ensure these ports are accessible:

| Protocol | Default Port | Used By | Required For | Firewall Note |
|----------|-------------|---------|--------------|---------------|
| SQL Database Engine | 1433 | `Get-DbaDatabase` | 62% of commands | Allow inbound on SQL Server |
| WS-Management | 5985/5986 | `New-DbaClientAlias` | 25% of commands | Windows Remote Management |
| SQL WMI | 135 | `Enable-DbaAgHadr` | 4% of commands | DCOM/RPC endpoint mapper |
| SMB | 445 | `Backup-DbaDatabase` | 4% of commands | File sharing for backups |

**Firewall Tip:** Create a dedicated Windows Firewall rule group for dbatools management traffic.

## Common Use Cases

### Backups & Restores
```powershell
# Backup all databases
Get-DbaDatabase -SqlInstance sql01 | Backup-DbaDatabase

# Simple restore
Restore-DbaDatabase -SqlInstance sql01 -Path "C:\temp\mydb.bak"

# Test ALL your backups on a different server
Test-DbaLastBackup -SqlInstance sql01 -Destination sql02 | Out-GridView
```

### Migrations
```powershell
# Migrate entire SQL instance with one command
$params = @{
    Source = 'sql01'
    Destination = 'sql02'
    BackupRestore = $true
    SharedPath = '\\nas\temp'
}
Start-DbaMigration @params -Force

# Copy jobs between servers
Copy-DbaAgentJob -Source sql01 -Destination sql02
```

### Monitoring & Health
```powershell
# Find databases without recent backups
Get-DbaLastBackup -SqlInstance sql01 |
    Where-Object LastFullBackup -lt (Get-Date).AddDays(-7)

# Check for corruption
Get-DbaLastGoodCheckDb -SqlInstance sql01 | Out-GridView

# Monitor currently running queries
Install-DbaWhoIsActive -SqlInstance sql01 -Database master
Invoke-DbaWhoIsActive -SqlInstance sql01
```

### Finding & Discovery
```powershell
# Find databases across multiple servers
Find-DbaDatabase -SqlInstance sql01, sql02, sql03 -Pattern "Production"

# Find stored procedures containing specific text
Find-DbaStoredProcedure -SqlInstance sql01 -Pattern "INSERT INTO Audit"

# Discover SQL instances on network
Find-DbaInstance -ComputerName server01, server02
```

## Installation

### Prerequisites
```powershell
# Check your PowerShell version
$PSVersionTable.PSVersion

# Set execution policy (one-time setup)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Trust PowerShell Gallery (one-time setup)
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
```

### Install Methods

#### For Current User (Recommended)
```powershell
Install-Module dbatools -Scope CurrentUser
```

#### For All Users (Requires Admin)
```powershell
Install-Module dbatools
```

#### Offline Installation
```powershell
# On internet-connected machine:
Save-Module -Name dbatools -Path C:\temp

# Copy to target machine and place in:
# - All users: C:\Program Files\WindowsPowerShell\Modules
# - Current user: $HOME\Documents\WindowsPowerShell\Modules

# Import the module after copying
Import-Module dbatools
```

### ⚠️ Certificate Change Notice (v2.5.5+)
Starting with v2.5.5, dbatools uses Microsoft Azure Trusted Signing. When upgrading from older versions:
```powershell
Install-Module dbatools -Force -SkipPublisherCheck
```
[Full migration guide →](https://blog.netnerds.net/2025/08/dbatools-azure-trusted-signing/)

## Getting Help

```powershell
# Detailed help for any command
Get-Help Test-DbaLastBackup -Full

# Find commands
Get-Command -Module dbatools *backup*
Find-DbaCommand -Tag Migration

# Online help
Get-Help Test-DbaLastBackup -Online
```

**Resources:**
- 📚 [Documentation](https://docs.dbatools.io)
- 🔍 [Command Reference](https://dbatools.io/commands)
- 📰 [Blog](https://dbatools.io/blog)
- 💬 [Slack Community](https://dbatools.io/slack)

## Advanced Usage

### Authentication

#### SQL Authentication
```powershell
$cred = Get-Credential sqladmin
Get-DbaDatabase -SqlInstance sql01 -SqlCredential $cred
```

#### Alternative Windows Credentials
```powershell
$cred = Get-Credential ad\winadmin
Get-DbaDiskSpace -ComputerName sql01 -Credential $cred
```

#### Storing Credentials Securely
PowerShell's `Export-CliXml` provides a fast and secure way to store credentials to disk. The credentials are encrypted using Windows Data Protection API (DPAPI) and can only be decrypted by the same user on the same machine.

```powershell
# Save credentials to disk (one-time setup)
Get-Credential | Export-CliXml -Path "$HOME\sql-credentials.xml"

# Reuse saved credentials in scripts
$cred = Import-CliXml -Path "$HOME\sql-credentials.xml"
Get-DbaDatabase -SqlInstance sql01 -SqlCredential $cred
```

For more advanced credential management approaches including the Secrets Management module, see [Rob Sewell's guide](https://blog.robsewell.com/blog/good-bye-import-clixml-use-the-secrets-management-module-for-your-labs-and-demos/).

### Custom Ports
```powershell
# Using colon or comma for non-default ports
Get-DbaDatabase -SqlInstance 'sql01:55559'
Get-DbaDatabase -SqlInstance 'sql01,55559'  # Note: quotes required
```

### PowerShell Transcript
```powershell
# Import module before starting transcript (PS 5.1 requirement)
Import-Module dbatools
Start-Transcript
Get-DbaDatabase -SqlInstance sql01
Stop-Transcript
```

## Troubleshooting

### Using with Azure PowerShell (Az) or SqlServer Modules

If you use dbatools alongside the Az PowerShell module or Microsoft's SqlServer module in the same session, import them in this order to avoid assembly version conflicts:

```powershell
# 1. Import Az or SqlServer modules first
Import-Module Az.Accounts
Import-Module SqlServer

# 2. Then import dbatools
Import-Module dbatools
```

If you still experience conflicts or need to use dbatools with other modules that have assembly conflicts, use the `-ArgumentList $true` parameter to enable conflict avoidance mode:

```powershell
Import-Module dbatools -ArgumentList $true
```

This skips loading conflicting Azure assemblies when incompatible versions are already loaded.

### Common Issues

**Issue: "Could not connect to SqlInstance"**
```powershell
# Test connectivity
Test-DbaConnection -SqlInstance sql01

# Check if SQL Browser service is running for named instances
Get-DbaService -ComputerName sql01 -Type Browser
```

**Issue: "Access denied" errors**
```powershell
# Ensure you have proper SQL permissions
Get-DbaLogin -SqlInstance sql01 -Login $env:USERNAME

# For Windows authentication issues, verify domain connectivity
Test-ComputerSecureChannel
```

**Issue: Module won't import**
```powershell
# Check execution policy
Get-ExecutionPolicy

# Force reimport if needed
Remove-Module dbatools -Force -ErrorAction SilentlyContinue
Import-Module dbatools -Force
```

For more troubleshooting help, visit our [troubleshooting guide](https://dbatools.io/troubleshooting/) or ask in [Slack](https://dbatools.io/slack).

## Community & Support

**Get Involved:**
- ⭐ Star this repository
- 🐛 [Report issues](https://github.com/dataplat/dbatools/issues)
- 💡 [Request features](https://github.com/dataplat/dbatools/issues)
- 🤝 [Contribute code](CONTRIBUTING.md)

**Community Channels:**
- [#dbatools on SQL Community Slack](https://sqlcommunity.slack.com/messages/C1M2WEASG/)
- [#dbatools-dev for contributors](https://sqlcommunity.slack.com/messages/C3EJ852JD/)
- [Twitter/X](https://twitter.com/psdbatools)

**Stats:**
- 📦 7+ million downloads on [PowerShell Gallery](https://www.powershellgallery.com/packages/dbatools)
- 👥 250+ contributors
- 🎯 700+ commands
- 🚀 10+ years of active development

## Contributing

We'd love to have you join us! Check out our [Contributing Guide](contributing.md) and the [dbatools-dev Slack channel](https://sqlcommunity.slack.com/messages/C3EJ852JD/).

## License

dbatools is licensed under the [MIT License](LICENSE).

## Special Thanks

Thank you to all our [contributors](https://github.com/dataplat/dbatools/graphs/contributors) and the SQL Server community for making this project possible.
