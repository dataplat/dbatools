# SQL Server Version Support Guide

**GUIDING PRINCIPLE**: Support SQL Server 2000 when feasible and not overly complex. Balance maintenance burden with real-world user needs.

## Version Number Mapping

| SQL Server Version | VersionMajor | Check Example |
|-------------------|--------------|---------------|
| SQL Server 2000 | 8 | `$server.VersionMajor -eq 8` |
| SQL Server 2005 | 9 | `$server.VersionMajor -eq 9` |
| SQL Server 2008/2008 R2 | 10 | `$server.VersionMajor -eq 10` |
| SQL Server 2012 | 11 | `$server.VersionMajor -eq 11` |
| SQL Server 2014 | 12 | `$server.VersionMajor -eq 12` |
| SQL Server 2016 | 13 | `$server.VersionMajor -eq 13` |
| SQL Server 2017 | 14 | `$server.VersionMajor -eq 14` |
| SQL Server 2019 | 15 | `$server.VersionMajor -eq 15` |
| SQL Server 2022 | 16 | `$server.VersionMajor -eq 16` |
| SQL Server 2025 | 17 | `$server.VersionMajor -eq 17` |

## Philosophy

- **Support SQL Server 2000 when it is not complex or does not add significantly to the codebase**
- **Skip SQL Server 2000 gracefully when the feature requires SQL 2005+ functionality**
- Never be dismissive or judgmental about users running old SQL Server versions
- Respect that users may be dealing with legacy systems beyond their control
- Balance maintenance and support - practical, not ideological

## Three Patterns for Version Handling

### 1. MinimumVersion Parameter (Most Common for SQL 2005+ Features)

```powershell
# Requires SQL Server 2005 or higher
$server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9

# Results in clear error message:
# "SQL Server version 9 required - server not supported."
```

### 2. Direct Version Checking with throw

For features unavailable in older versions:

```powershell
# When feature is only available in SQL 2005+
if ($sourceServer.VersionMajor -lt 9 -or $destServer.VersionMajor -lt 9) {
    throw "Server AlertCategories are only supported in SQL Server 2005 and above. Quitting."
}
```

### 3. Conditional Logic for Backward Compatibility

When SQL 2000 support is feasible:

```powershell
# Different queries or logic for SQL Server 2000
if ($server.VersionMajor -eq 8) {
    # SQL Server 2000 uses different system tables
    $HeaderInfo = Get-BackupAncientHistory -SqlInstance $server -Database $dbName
} else {
    # SQL Server 2005+ uses catalog views
    $HeaderInfo = Get-DbaDbBackupHistory -SqlInstance $server -Database $dbName
}

# SQL Server 2000 may need different default paths
if ($null -eq $PSBoundParameters.Path -and $server.VersionMajor -eq 8) {
    $Path = (Get-DbaDefaultPath -SqlInstance $server).Backup
}
```

## Common Reasons to Require SQL Server 2005+

SQL Server 2005 introduced many foundational changes that make backward compatibility difficult:
- Catalog views (`sys.*`) replaced system tables (`sysobjects`, `syscomments`, etc.)
- `SCHEMA_NAME()` and schema-based security
- New object types and features (e.g., Service Broker, CLR integration)
- DMVs (Dynamic Management Views)
- Deprecated features like Extended Stored Procedures (deprecated in 2005, favor CLR)

## When to Use Each Pattern

| Pattern | Use When |
|---------|----------|
| MinimumVersion 9 | Feature fundamentally requires SQL 2005+ (catalog views, schemas, DMVs) |
| Explicit version check | Need clearer error message or version-specific logic paths |
| Conditional logic | SQL 2000 support is straightforward (different system tables, minor syntax differences) |

## Documentation Standards

When a command requires a specific SQL Server version, document it in the help:

```powershell
.PARAMETER SqlInstance
    The target SQL Server instance or instances. Must be SQL Server 2005 or higher.

.PARAMETER Source
    Source SQL Server instance. You must have sysadmin access and server version must be SQL Server 2000 or higher.
```

## Examples from the Codebase

### Commands that Support SQL Server 2000
- `Copy-DbaAgentAlert`, `Copy-DbaAgentJob`, `Copy-DbaAgentOperator`, `Copy-DbaAgentProxy`, `Copy-DbaAgentServer`
- `Copy-DbaBackupDevice`, `Copy-DbaCustomError`, `Copy-DbaLogin`
- `Backup-DbaDatabase` (with version-specific handling)
- `Copy-DbaDatabase` (with restrictions: cannot migrate SQL 2000 to SQL 2012+)

### Commands that Require SQL Server 2005+
- `Copy-DbaAgentJobCategory` (uses AlertCategories only available in SQL 2005+)
- `Copy-DbaAgentProxy` (uses MinimumVersion 9)
- Most commands using catalog views, DMVs, or SQL 2005+ features

## Important

Never be dismissive or judgmental about users running old SQL Server versions. Provide respectful, factual, technical explanations.
