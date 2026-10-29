# SQL Server Version Support Guide

**GUIDING PRINCIPLE**: SQL Server 2008 is the oldest version dbatools supports. `Connect-DbaInstance` refuses anything older, because SMO 181 - which dbatools.library ships since 2026.5.3 and dbatools requires since 2.8.3 - no longer supports it. **dbatools 2.8.2 with dbatools.library 2025.12.28 is the last release that supports SQL Server 2000 and 2005** (#10812).

## Version Number Mapping

| SQL Server Version | VersionMajor | Check Example |
|-------------------|--------------|---------------|
| SQL Server 2000 | 8 | Refused by `Connect-DbaInstance` |
| SQL Server 2005 | 9 | Refused by `Connect-DbaInstance` |
| SQL Server 2008/2008 R2 | 10 | `$server.VersionMajor -eq 10` |
| SQL Server 2012 | 11 | `$server.VersionMajor -eq 11` |
| SQL Server 2014 | 12 | `$server.VersionMajor -eq 12` |
| SQL Server 2016 | 13 | `$server.VersionMajor -eq 13` |
| SQL Server 2017 | 14 | `$server.VersionMajor -eq 14` |
| SQL Server 2019 | 15 | `$server.VersionMajor -eq 15` |
| SQL Server 2022 | 16 | `$server.VersionMajor -eq 16` |
| SQL Server 2025 | 17 | `$server.VersionMajor -eq 17` |

## Philosophy

- **Support SQL Server 2008 and later.** Every connection goes through `Connect-DbaInstance`, which refuses older instances with a message that names the last release supporting them, so no command needs its own check for SQL Server 2000 or 2005.
- **Do not add new SQL Server 2000 or 2005 code paths.** The existing `-eq 8` and `-eq 9` branches are unreachable now. Remove them when you change the code around them anyway.
- **Skip gracefully when a feature needs a version newer than 2008.**
- Never be dismissive or judgmental about users running old SQL Server versions
- Respect that users may be dealing with legacy systems beyond their control
- Balance maintenance and support - practical, not ideological

## Three Patterns for Version Handling

### 1. MinimumVersion Parameter (Most Common for Features Newer than SQL 2008)

```powershell
# Requires SQL Server 2012 or higher
$server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11

# Results in clear error message:
# "SQL Server version 11 required - server not supported."
```

`MinimumVersion 9` and `MinimumVersion 10` add nothing any more: `Connect-DbaInstance` refuses everything below 10 whether or not the parameter is given - see [The Floor SMO Enforces](#the-floor-smo-enforces).

### 2. Direct Version Checking with throw

For features unavailable in older versions:

```powershell
# When feature is only available in SQL 2012+
if ($sourceServer.VersionMajor -lt 11 -or $destServer.VersionMajor -lt 11) {
    throw "Availability groups are only supported in SQL Server 2012 and above. Quitting."
}
```

### 3. Conditional Logic for Backward Compatibility

When supporting an older version is straightforward:

```powershell
# SQL Server 2022 and above - exclude ActiveConnections due to performance issue #9282
if ($server.VersionMajor -ge 16) {
    $fields = $Fields201x_Db | Where-Object { $PSItem -ne "ActiveConnections" }
} else {
    $fields = $Fields201x_Db
}
```

## The Floor SMO Enforces

SMO has its own floor, and since SMO 181 it is SQL Server 2008 for practically the whole object model.

`Microsoft.SqlServer.SqlEnum.dll` in `dbatools.library` carries one XML definition per enumerated object, each declaring the oldest version it supports. In SMO 172.76.0 (assembly 17.100), the last build dbatools shipped before 181, `Server.xml`, `Information.xml`, `Database.xml`, `Login.xml` and `backupset.xml` open with `min_major='7'` and carry separate query branches for SQL Server 7.0/2000 and 2005. In SMO 181 (assembly 18.100, dbatools.library 2026.5.3 and later) every one of them opens with `min_major='10'`, and the SMO changelog for 181.12.0 says: "Remove SQL Server 2005 and prior version support". Re-check it against whatever version is pinned in `.github/dbatools-library-version.json` before relying on the numbers:

```powershell
$assembly = [Reflection.Assembly]::LoadFrom("$smoPath\Microsoft.SqlServer.SqlEnum.dll")
$stream = $assembly.GetManifestResourceStream("Database.xml")
(New-Object System.IO.StreamReader($stream)).ReadToEnd() -match "min_major='(\d+)'"
```

What follows from that on an instance older than 2008, measured against a real SQL Server 2005:

- **The connection itself still works.** The TDS login succeeds and plain T-SQL returns results. Only the object model fails.
- **`$server.Databases`, `$server.Logins` and the other collections throw** `'CONNECTIONPROPERTY' is not a recognized built-in function name`.
- **`$server.VersionMajor` is itself unreadable**, because `Information.xml` is one of the 2008+ definitions. `VersionString`, `Edition`, `ProductLevel` and `ConnectionContext.ServerVersion` come back empty as well.
- **`SERVERPROPERTY('ProductVersion')` does answer**, returning `9.00.5000.00` on that instance. It has been available since SQL Server 2000 and is plain T-SQL, so it can be read wherever the connection itself works.

That is why `Connect-DbaInstance` reads the version from `VersionMajor`, then `ConnectionContext.ServerVersion`, then `SERVERPROPERTY('ProductVersion')` - the common case costs no round trip - and refuses the connection when it is below 10. If none of the three knows the version the connection is allowed through. Background: [#10583](https://github.com/dataplat/dbatools/issues/10583), [#10812](https://github.com/dataplat/dbatools/issues/10812).

SQL Server 2000 is further out of reach than that: from PowerShell 7 the login itself fails with "Internal connection fatal error", before any version can be read ([#8425](https://github.com/dataplat/dbatools/issues/8425)). The last release that supports it only does so from Windows PowerShell 5.1.

## When to Use Each Pattern

| Pattern | Use When |
|---------|----------|
| MinimumVersion 11 or higher | Feature fundamentally requires a version newer than SQL 2008 |
| Explicit version check | Need clearer error message or version-specific logic paths |
| Conditional logic | Supporting an older version is straightforward (different system views, minor syntax differences) |

## Documentation Standards

When a command requires a version newer than SQL Server 2008, document it in the help:

```powershell
.PARAMETER SqlInstance
    The target SQL Server instance or instances. Must be SQL Server 2012 or higher.
```

## Important

Never be dismissive or judgmental about users running old SQL Server versions. Provide respectful, factual, technical explanations. Users on SQL Server 2000 or 2005 should be pointed to dbatools 2.8.2 with dbatools.library 2025.12.28, as the `Connect-DbaInstance` message and the README do.
