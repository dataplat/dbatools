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

`MinimumVersion 9` is the right guard only for commands that stay in T-SQL. Anything that walks SMO's object model needs 10 - see [The Floor SMO Enforces](#the-floor-smo-enforces).

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

## The Floor SMO Enforces

The version table at the top of this guide describes the T-SQL surface. SMO has its own, higher floor, and it applies to every command that walks the object model rather than issuing raw queries.

`Microsoft.SqlServer.SqlEnum.dll` in `dbatools.library` carries one XML definition per enumerated object, each declaring the oldest version it supports. In the 2026.5.3 build (SMO 18.100.1.19), `Server.xml`, `Information.xml`, `Database.xml` and `Login.xml` all open with `min_major='10'`, and 224 of the 298 definitions that declare a floor declare 10. Re-check it against whatever version is pinned in `.github/dbatools-library-version.json` before relying on the numbers:

```powershell
$assembly = [Reflection.Assembly]::LoadFrom("$smoPath\Microsoft.SqlServer.SqlEnum.dll")
$stream = $assembly.GetManifestResourceStream("Database.xml")
(New-Object System.IO.StreamReader($stream)).ReadToEnd() -match "min_major='(\d+)'"
```

What follows from that:

- **`$server.Databases`, `$server.Logins` and the other collections need SQL Server 2008.** Below that they throw `'CONNECTIONPROPERTY' is not a recognized built-in function name`.
- **`$server.VersionMajor` is itself unreadable below 2008**, because `Information.xml` is one of the 2008+ definitions. `VersionString`, `Edition` and `ProductLevel` come back empty for the same reason.
- **Version branches misroute on such an instance.** `-eq 8` and `-eq 9` are both false against an empty `VersionMajor`, so the legacy path is skipped and the modern one runs anyway. Comparisons written as `-lt` fail safe by accident, since `$null -lt 9` is `$true`.
- **`ConnectionContext.ServerVersion` is empty below 2008 as well.** It reads as a different code path from the enumerators, so it looks like a way around them, but on a real SQL Server 2005 instance it returns nothing just like `VersionMajor`.
- **`SERVERPROPERTY('ProductVersion')` does answer there**, returning `9.00.5000.00` on that same instance. It has been available since SQL Server 2000 and is plain T-SQL, so it can be read wherever the connection itself works. That is what `Connect-DbaInstance -MinimumVersion` falls back to, after trying `VersionMajor` and `ConnectionContext.ServerVersion` first so the common case costs no round trip. If none of the three knows the version the connection is allowed through, as it was before the fallback existed.

So use `MinimumVersion 10` and document "SQL Server 2008 or higher" for anything touching SMO collections. Reserve `MinimumVersion 9` for commands that only issue T-SQL. Background: [#10583](https://github.com/dataplat/dbatools/issues/10583).

## When to Use Each Pattern

| Pattern | Use When |
|---------|----------|
| MinimumVersion 9 | Feature fundamentally requires SQL 2005+ (catalog views, schemas, DMVs) **and the command stays in T-SQL** |
| MinimumVersion 10 | Command walks SMO's object model (`Databases`, `Logins`, ...) - SMO's own floor |
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
