# dbatools

<img align="left" src=bin/dbatools.png alt="dbatools logo"> Migrate SQL Server instances in minutes instead of days. Test hundreds of backups automatically. Find that one database across 50 servers. dbatools is a PowerShell module with nearly 700 commands that replace manual SQL Server administration with powerful and fun automation.

Works everywhere on-prem: SQL Server 2000-current, Windows/Linux/macOS, Express-Enterprise. Plus a little bit of Azure.

## Table of Contents
- [Quick Start](#quick-start)
  - [Installation](#installation)
  - [First Commands](#first-commands)
- [Common Use Cases](#common-use-cases)
  - [Backups & Restores](#backups--restores)
  - [Migrations](#migrations)
  - [Monitoring & Health](#monitoring--health)
  - [Finding & Discovery](#finding--discovery)
- [Advanced Usage](#advanced-usage)
  - [Authentication](#authentication)
  - [Custom Ports](#custom-ports)
  - [PowerShell Transcript](#powershell-transcript)
- [Support & Compatibility](#support--compatibility)
- [Community & Help](#community--help)
- [Contributing](#contributing)

## Quick Start

### Installation

dbatools works on Windows, Linux and macOS. Windows requires PowerShell v3 and above, while PowerShell Core requires 7.4.0 and above.

```powershell
# Install from PowerShell Gallery
Install-Module dbatools -Scope CurrentUser

# For servers or all users, run elevated without -Scope
Install-Module dbatools
```

📦 **[View dbatools on PowerShell Gallery](https://www.powershellgallery.com/packages/dbatools)** - 50+ million downloads and counting!

For older PowerShell versions without Gallery support, download `PowerShellGet` from [Microsoft's site](https://learn.microsoft.com/en-us/powershell/scripting/gallery/installing-psget?view=powershell-7.4).

### ⚠️ Important: Certificate Change (August 2025)

Starting with v2.5.5, dbatools uses Microsoft Azure Trusted Signing instead of DigiCert. This means:
- **Better security**: Microsoft backs our reputation, fewer antivirus false positives
- **One-time upgrade hiccup**: When upgrading from older versions, use:
  ```powershell
  Update-Module dbatools -Force -SkipPublisherCheck
  ```
- **ExecutionPolicy users**: If you use AllSigned/RemoteSigned, you'll need to trust the new certificate after each update.

Most users won't notice any difference, but those with strict execution policies should read the [full migration guide](https://blog.netnerds.net/2025/08/dbatools-azure-trusted-signing/) including automation scripts.

### First Commands

```powershell
# See your databases
Get-DbaDatabase -SqlInstance localhost

# Check your backups
Get-DbaLastBackup -SqlInstance localhost | Format-Table

# Test your last backup (yes, really!)
Test-DbaLastBackup -SqlInstance localhost
```

## Common Use Cases

### Backups & Restores

```powershell
# Backup all databases
Get-DbaDatabase -SqlInstance sql01 | Backup-DbaDatabase

# Simple restore
Restore-DbaDatabase -SqlInstance sql01 -Path "C:\temp\mydb.bak"

# Restore entire instance from Ola Hallengren backups
Get-ChildItem -Directory \\nas\backups\sql01 | Restore-DbaDatabase -SqlInstance sql02

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

# Export/Import logins with passwords
Export-DbaLogin -SqlInstance sql01 -Path C:\temp\logins.sql
Invoke-DbaQuery -SqlInstance sql02 -File C:\temp\logins.sql

# Copy jobs between servers
Copy-DbaAgentJob -Source sql01 -Destination sql02
```

### Monitoring & Health

```powershell
# Find databases without recent backups
Get-DbaLastBackup -SqlInstance sql01 | Where-Object LastFullBackup -lt (Get-Date).AddDays(-7)

# Check for corruption
Get-DbaLastGoodCheckDb -SqlInstance sql01 | Out-GridView

# Monitor currently running queries
Install-DbaWhoIsActive -SqlInstance sql01 -Database master
Invoke-DbaWhoIsActive -SqlInstance sql01

# Get disk space for all databases
Get-DbaDbSpace -SqlInstance sql01 | Out-GridView
```

### Finding & Discovery

```powershell
# Find databases across multiple servers
Find-DbaDatabase -SqlInstance sql01, sql02, sql03 -Pattern "Production"

# Find stored procedures containing specific text
Find-DbaStoredProcedure -SqlInstance sql01 -Pattern "INSERT INTO Audit"

# Find orphaned database files
Find-DbaOrphanedFile -SqlInstance sql01

# Discover SQL instances on network
Find-DbaInstance -ComputerName server01, server02
```

## Advanced Usage

### Authentication

#### SQL Server Authentication

By default, all SQL-based commands use Windows Authentication. To use SQL logins or alternative Windows credentials:

```powershell
# SQL Login
$cred = Get-Credential sqladmin
Get-DbaDatabase -SqlInstance sql01 -SqlCredential $cred
```

<a href="https://dbatools.io/wp-content/uploads/2016/05/cred.jpg"><img class="aligncenter size-full wp-image-6897" src="https://dbatools.io/wp-content/uploads/2016/05/cred.jpg" alt="" width="322" height="261" /></a>

#### Alternative Windows Credentials

For commands that access Windows (like `Get-DbaDiskSpace`), use the `-Credential` parameter:

```powershell
$cred = Get-Credential ad\winadmin
Get-DbaDiskSpace -ComputerName sql01 -Credential $cred
```

For secure credential storage, see [Jaap Brasser's guide](https://www.jaapbrasser.com/quickly-and-securely-storing-your-credentials-powershell/).

### Custom Ports

```powershell
# Using colon or comma for non-default ports
Get-DbaDatabase -SqlInstance 'sql01:55559'
Get-DbaDatabase -SqlInstance 'sql01,55559'  # Note the quotes required for comma
```

### PowerShell Transcript

```powershell
# Import module before starting transcript (PS 5.1 requirement)
Import-Module dbatools
Start-Transcript
Get-DbaDatabase -SqlInstance sql01
Stop-Transcript
```

## Support & Compatibility

We support a wide range of SQL Server versions and platforms:

| Component | Versions |
|-----------|----------|
| SQL Server | 2000 - Current |
| PowerShell (Windows) | v3 and above |
| PowerShell Core | 7.4.0+ |
| Operating Systems | Windows, Linux, macOS (Intel & M1) |
| Editions | Express through Datacenter |
| Configurations | Clustered, AG, Stand-alone, Named instances |

We maintain backward compatibility with older systems still in production use.

## Community & Help

**Documentation:** https://docs.dbatools.io
**Command Reference:** https://dbatools.io/commands
**Blog:** https://dbatools.io/blog

**Slack Community:**
- [#dbatools](https://sqlcommunity.slack.com/messages/C1M2WEASG/) - General discussion
- [#dbatools-dev](https://sqlcommunity.slack.com/messages/C3EJ852JD/) - Development discussion
- [Get invite](https://dbatools.io/slack/)

**Getting Help:**
```powershell
# Detailed help for any command
Get-Help Test-DbaLastBackup -Full

# Find commands
Get-Command -Module dbatools *backup*

# Online help
Get-Help Test-DbaLastBackup -Online
```

## Contributing

Want to contribute? We'd love to have you!

- Read our [Contributing Guide](CONTRIBUTING.md)
- Check out the [dbatools-dev Slack channel](https://sqlcommunity.slack.com/messages/C3EJ852JD/)
- Visit [dbatools.io/team](https://dbatools.io/team) to learn about joining the team
- Star this repository if you find it useful ⭐

## License

dbatools is licensed under the [MIT License](LICENSE).

## Special Thanks

Thank you to all our [contributors](https://github.com/dataplat/dbatools/graphs/contributors) and the SQL Server community for making this project possible.