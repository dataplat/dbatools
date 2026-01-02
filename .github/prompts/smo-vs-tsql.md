# SMO vs T-SQL Usage Guide

**GUIDING PRINCIPLE**: Default to using SMO (SQL Server Management Objects) first. Only use T-SQL when SMO doesn't provide the functionality or when T-SQL offers better performance or user experience.

## Why SMO First

- **Abstraction**: SMO provides object-oriented interface that handles version differences automatically
- **Type Safety**: Strong typing reduces errors compared to dynamic T-SQL strings
- **Built-in Methods**: Common operations (Create, Drop, Alter, Script) are provided out-of-the-box
- **Consistency**: SMO ensures consistent behavior across SQL Server versions
- **Less Code**: Often requires fewer lines than equivalent T-SQL

## When to Use SMO

### 1. Object Manipulation
Creating, dropping, altering database objects:

```powershell
# PREFERRED - SMO for object manipulation
$newdb = New-Object Microsoft.SqlServer.Management.Smo.Database($server, $dbName)
$newdb.Collation = $Collation
$newdb.RecoveryModel = $RecoveryModel
$newdb.Create()

# Dropping objects
$destServer.Roles[$roleName].Drop()
$destServer.Roles.Refresh()
```

### 2. Object Scripting
Generating T-SQL from existing objects:

```powershell
# PREFERRED - SMO scripting with execution via Query
$sql = $currentRole.Script() | Out-String
Write-Message -Level Debug -Message $sql
$destServer.Query($sql)

# Another example
$destServer.Query($currentEndpoint.Script()) | Out-Null
```

### 3. Object Enumeration
Accessing collections and properties:

```powershell
# PREFERRED - SMO for object access
$databases = $server.Databases
$database = $server.Databases[$dbName]
$isSystemDb = $database.IsSystemObject
$members = $currentRole.EnumMemberNames()
```

### 4. Object Properties
Reading and setting object attributes:

```powershell
# PREFERRED - SMO for property access
$recoveryModel = $db.RecoveryModel
$owner = $db.Owner
$lastBackup = $db.LastBackupDate
$size = $db.Size
```

## When T-SQL is Appropriate

### 1. System Views and DMVs
When SMO doesn't expose the data efficiently:

```powershell
# T-SQL for system catalog queries
$sql = @"
SELECT
    p.name AS ProcedureName,
    SCHEMA_NAME(p.schema_id) AS SchemaName,
    p.object_id,
    m.definition AS DllPath
FROM sys.procedures p
INNER JOIN sys.all_objects o ON p.object_id = o.object_id
LEFT JOIN sys.sql_modules m ON p.object_id = m.object_id
WHERE p.type = 'X'
    AND p.is_ms_shipped = 0
ORDER BY p.name
"@
$sourceXPs = $sourceServer.Query($sql)
```

### 2. Performance-Critical Queries
When retrieving large result sets:

```powershell
# T-SQL for efficient data retrieval
$querylastused = "SELECT dbname, max(last_read) last_read FROM sys.dm_db_index_usage_stats GROUP BY dbname"
$dblastused = $server.Query($querylastused)
```

### 3. Version-Specific Logic
Different queries for different SQL Server versions:

```powershell
# T-SQL when version-specific system tables/views are needed
if ($server.VersionMajor -eq 8) {
    # SQL Server 2000 uses system tables
    $backed_info = $server.Query("SELECT name, SUSER_SNAME(sid) AS [Owner] FROM master.dbo.sysdatabases")
} else {
    # SQL Server 2005+ uses catalog views
    $backed_info = $server.Query("SELECT name, SUSER_SNAME(owner_sid) AS [Owner] FROM sys.databases")
}
```

### 4. System Stored Procedures
When the operation requires a specific system proc:

```powershell
# T-SQL for system procedures that have no SMO equivalent
$dropSql = "EXEC sp_dropextendedproc @functname = N'$xpFullName'"
$null = $destServer.Query($dropSql)

$createSql = "EXEC sp_addextendedproc @functname = N'$xpFullName', @dllname = N'$destDllPath'"
$null = $destServer.Query($createSql)
```

### 5. User-Friendly Features
When T-SQL makes the command more intuitive:

```powershell
# Sometimes T-SQL provides better UX than SMO
# Example: Parameterized queries for filtering
$splatQuery = @{
    SqlInstance  = $instance
    Query        = "SELECT * FROM users WHERE Givenname = @name"
    SqlParameter = @{ Name = "Maria" }
}
$result = Invoke-DbaQuery @splatQuery
```

## Hybrid Pattern (Most Common)

Most dbatools commands use both SMO and T-SQL strategically:

```powershell
# Get SMO server object
$sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential

# Use SMO for object enumeration
$sourceRoles = $sourceServer.Roles | Where-Object IsFixedRole -eq $false

# Use T-SQL for complex permission queries
$splatPermissions = @{
    SqlInstance        = $sourceServer
    IncludeServerLevel = $true
}
$sourcePermissions = Get-DbaPermission @splatPermissions | Where-Object Grantee -eq $roleName

# Use SMO for object manipulation
foreach ($currentRole in $sourceRoles) {
    # Script the object using SMO
    $sql = $currentRole.Script() | Out-String

    # Execute via T-SQL
    $destServer.Query($sql)

    # Use SMO methods for membership
    $members = $currentRole.EnumMemberNames()
    foreach ($member in $members) {
        $destServer.Roles[$roleName].AddMember($member)
    }
}
```

## Decision Tree

1. **Does SMO expose the functionality cleanly?**
   - YES → Use SMO
   - NO → Continue to #2

2. **Is this a data retrieval operation from system views/DMVs?**
   - YES → Use T-SQL via `$server.Query()`
   - NO → Continue to #3

3. **Does the operation require a system stored procedure?**
   - YES → Use T-SQL via `$server.Query()`
   - NO → Continue to #4

4. **Would T-SQL significantly improve user experience?**
   - YES → Use T-SQL (document why in comments)
   - NO → Use SMO

## Common Patterns

```powershell
# Pattern 1: SMO object with T-SQL execution of Script()
$sql = $smoObject.Script() | Out-String
$destServer.Query($sql)

# Pattern 2: T-SQL for discovery, SMO for manipulation
$objects = $server.Query("SELECT name FROM sys.objects WHERE type = 'U'")
foreach ($obj in $objects) {
    $table = $server.Databases[$dbName].Tables[$obj.name]
    $table.Drop()  # SMO method
}

# Pattern 3: SMO with T-SQL fallback
try {
    $database = $server.Databases[$dbName]  # SMO
} catch {
    # Fallback to T-SQL if SMO fails
    $result = $server.Query("SELECT name FROM sys.databases WHERE name = '$dbName'")
}
```

## Anti-Patterns to Avoid

```powershell
# WRONG - Using T-SQL when SMO provides the functionality
$result = $server.Query("ALTER DATABASE [$dbName] SET RECOVERY FULL")

# CORRECT - Use SMO
$db = $server.Databases[$dbName]
$db.RecoveryModel = "Full"
$db.Alter()

# WRONG - Using T-SQL for object enumeration
$databases = $server.Query("SELECT name FROM sys.databases")

# CORRECT - Use SMO
$databases = $server.Databases

# WRONG - Concatenating T-SQL strings without parameters (SQL injection risk)
$result = $server.Query("SELECT * FROM users WHERE name = '$userName'")

# CORRECT - Use parameterized queries
$splatQuery = @{
    Query        = "SELECT * FROM users WHERE name = @userName"
    SqlParameter = @{ userName = $userName }
}
$result = Invoke-DbaQuery @splatQuery -SqlInstance $server
```

## Summary

- **Default to SMO** for object-oriented operations (Create, Drop, Alter, Script, property access)
- **Use T-SQL** for system views, DMVs, complex queries, system stored procedures, and version-specific logic
- **Combine both** in a hybrid approach when it provides the best balance of functionality and usability
- **Always prefer parameterized queries** when using T-SQL with dynamic values
- **Document your choice** when T-SQL is used instead of SMO for non-obvious reasons
