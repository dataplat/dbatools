# dbatools PowerShell Style Guide for Claude Code

This style guide provides coding standards for dbatools PowerShell development to ensure consistency, readability, and maintainability across the project.

## CRITICAL COMMAND SYNTAX RULES

### NO BACKTICKS - ALWAYS USE SPLATS

**ABSOLUTE RULE**: NEVER suggest or use backticks (`) for line continuation. Backticks are an anti-pattern in modern PowerShell development.

### PARAMETER ATTRIBUTES - NO `= $true` SYNTAX

**MODERN RULE**: Do NOT use `Mandatory = $true` or similar boolean attribute assignments. Boolean attributes do not require explicit value assignment in modern PowerShell.

```powershell
# CORRECT - Modern attribute syntax (no = $true)
param(
    [Parameter(Mandatory)]
    [string]$SqlInstance,

    [Parameter(ValueFromPipeline)]
    [object[]]$InputObject,

    [switch]$EnableException
)

# WRONG - Outdated PSv2 syntax (no longer needed)
param(
    [Parameter(Mandatory = $true)]
    [string]$SqlInstance,

    [Parameter(ValueFromPipeline = $true)]
    [object[]]$InputObject
)
```

**Guidelines:**
- Use `[Parameter(Mandatory)]` not `[Parameter(Mandatory = $true)]`
- Use `[switch]` for boolean flags, not `[bool]` parameters
- Keep non-boolean attributes with values: `[Parameter(ValueFromPipelineByPropertyName = "Name")]`
- Avoid ParameterSets - their error messages are terrible and hard to use. Use Test-Bound instead and provide users with useful, concrete error messages.
- No extra line breaks between parameter declarations - keep parameter blocks compact without blank lines separating individual parameters.

### POWERSHELL v3 COMPATIBILITY

**CRITICAL RULE**: dbatools must support PowerShell v3. NEVER use `::new()` or other PowerShell v5+ syntax constructs.

**Do NOT use:**
- `[ClassName]::new()` - Use `New-Object` instead
- Advanced type accelerators only available in v5+
- Other v5+ language features

```powershell
# CORRECT - PowerShell v3 compatible
$object = New-Object -TypeName System.Collections.Hashtable
$collection = New-Object System.Collections.ArrayList

# WRONG - PowerShell v5+ only
$object = [System.Collections.Hashtable]::new()
$collection = [System.Collections.ArrayList]::new()
```

When in doubt about version compatibility, use the `New-Object` cmdlet approach.

### SQL SERVER VERSION SUPPORT

**GUIDING PRINCIPLE**: Support SQL Server 2000 when feasible and not overly complex. Balance maintenance burden with real-world user needs.

**Version Number Mapping:**
- SQL Server 2000 = Version 8 (`$server.VersionMajor -eq 8`)
- SQL Server 2005 = Version 9 (`$server.VersionMajor -eq 9`)
- SQL Server 2008/2008 R2 = Version 10
- SQL Server 2012 = Version 11
- SQL Server 2014 = Version 12
- SQL Server 2016 = Version 13
- SQL Server 2017 = Version 14
- SQL Server 2019 = Version 15
- SQL Server 2022 = Version 16

**Philosophy:**
- **Support SQL Server 2000 when it is not complex or does not add significantly to the codebase**
- **Skip SQL Server 2000 gracefully when the feature requires SQL 2005+ functionality**
- Never be dismissive or judgmental about users running old SQL Server versions
- Respect that users may be dealing with legacy systems beyond their control
- Balance maintenance and support - practical, not ideological

**Three Patterns for Version Handling:**

1. **MinimumVersion Parameter** (most common for SQL 2005+ features):
```powershell
# Requires SQL Server 2005 or higher
$server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9

# Results in clear error message:
# "SQL Server version 9 required - server not supported."
```

2. **Direct Version Checking with throw** (for features unavailable in older versions):
```powershell
# When feature is only available in SQL 2005+
if ($sourceServer.VersionMajor -lt 9 -or $destServer.VersionMajor -lt 9) {
    throw "Server AlertCategories are only supported in SQL Server 2005 and above. Quitting."
}
```

3. **Conditional Logic for Backward Compatibility** (when SQL 2000 support is feasible):
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

**Common Reasons to Require SQL Server 2005+:**

SQL Server 2005 introduced many foundational changes that make backward compatibility difficult:
- Catalog views (`sys.*`) replaced system tables (`sysobjects`, `syscomments`, etc.)
- `SCHEMA_NAME()` and schema-based security
- New object types and features (e.g., Service Broker, CLR integration)
- DMVs (Dynamic Management Views)
- Deprecated features like Extended Stored Procedures (deprecated in 2005, favor CLR)

**When to Use Each Pattern:**

- **Use MinimumVersion 9** when the feature fundamentally requires SQL 2005+ (catalog views, schemas, DMVs)
- **Use explicit version checking** when you need a clearer error message or version-specific logic paths
- **Use conditional logic** when SQL 2000 support is straightforward (different system tables, minor syntax differences)

**Documentation Standards:**

When a command requires a specific SQL Server version, document it in the help:

```powershell
.PARAMETER SqlInstance
    The target SQL Server instance or instances. Must be SQL Server 2005 or higher.

.PARAMETER Source
    Source SQL Server instance. You must have sysadmin access and server version must be SQL Server 2000 or higher.
```

**Examples from the Codebase:**

Commands that support SQL Server 2000:
- `Copy-DbaAgentAlert`, `Copy-DbaAgentJob`, `Copy-DbaAgentOperator`, `Copy-DbaAgentProxy`, `Copy-DbaAgentServer`
- `Copy-DbaBackupDevice`, `Copy-DbaCustomError`, `Copy-DbaLogin`
- `Backup-DbaDatabase` (with version-specific handling)
- `Copy-DbaDatabase` (with restrictions: cannot migrate SQL 2000 to SQL 2012+)

Commands that require SQL Server 2005+:
- `Copy-DbaAgentJobCategory` (uses AlertCategories only available in SQL 2005+)
- `Copy-DbaAgentProxy` (uses MinimumVersion 9)
- Most commands using catalog views, DMVs, or SQL 2005+ features

**Important**: Never be dismissive or judgmental about users running old SQL Server versions. Provide respectful, factual, technical explanations.

### SMO vs T-SQL USAGE

**GUIDING PRINCIPLE**: Default to using SMO (SQL Server Management Objects) first. Only use T-SQL when SMO doesn't provide the functionality or when T-SQL offers better performance or user experience.

**Why SMO First:**
- **Abstraction**: SMO provides object-oriented interface that handles version differences automatically
- **Type Safety**: Strong typing reduces errors compared to dynamic T-SQL strings
- **Built-in Methods**: Common operations (Create, Drop, Alter, Script) are provided out-of-the-box
- **Consistency**: SMO ensures consistent behavior across SQL Server versions
- **Less Code**: Often requires fewer lines than equivalent T-SQL

**When to Use SMO:**

1. **Object Manipulation** - Creating, dropping, altering database objects:
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

2. **Object Scripting** - Generating T-SQL from existing objects:
```powershell
# PREFERRED - SMO scripting with execution via Query
$sql = $currentRole.Script() | Out-String
Write-Message -Level Debug -Message $sql
$destServer.Query($sql)

# Another example
$destServer.Query($currentEndpoint.Script()) | Out-Null
```

3. **Object Enumeration** - Accessing collections and properties:
```powershell
# PREFERRED - SMO for object access
$databases = $server.Databases
$database = $server.Databases[$dbName]
$isSystemDb = $database.IsSystemObject
$members = $currentRole.EnumMemberNames()
```

4. **Object Properties** - Reading and setting object attributes:
```powershell
# PREFERRED - SMO for property access
$recoveryModel = $db.RecoveryModel
$owner = $db.Owner
$lastBackup = $db.LastBackupDate
$size = $db.Size
```

**When T-SQL is Appropriate:**

1. **System Views and DMVs** - When SMO doesn't expose the data efficiently:
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

2. **Performance-Critical Queries** - When retrieving large result sets:
```powershell
# T-SQL for efficient data retrieval
$querylastused = "SELECT dbname, max(last_read) last_read FROM sys.dm_db_index_usage_stats GROUP BY dbname"
$dblastused = $server.Query($querylastused)
```

3. **Version-Specific Logic** - Different queries for different SQL Server versions:
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

4. **System Stored Procedures** - When the operation requires a specific system proc:
```powershell
# T-SQL for system procedures that have no SMO equivalent
$dropSql = "EXEC sp_dropextendedproc @functname = N'$xpFullName'"
$null = $destServer.Query($dropSql)

$createSql = "EXEC sp_addextendedproc @functname = N'$xpFullName', @dllname = N'$destDllPath'"
$null = $destServer.Query($createSql)
```

5. **User-Friendly Features** - When T-SQL makes the command more intuitive:
```powershell
# Sometimes T-SQL provides better UX than SMO
# Example: Parameterized queries for filtering
$splatQuery = @{
    SqlInstance = $instance
    Query       = "SELECT * FROM users WHERE Givenname = @name"
    SqlParameter = @{ Name = "Maria" }
}
$result = Invoke-DbaQuery @splatQuery
```

**Hybrid Pattern (Most Common):**

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

**Decision Tree:**

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

**Common Patterns:**

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

**Copy-DbaExtendedStoredProcedure Analysis:**

The newly created `Copy-DbaExtendedStoredProcedure` command demonstrates proper SMO vs T-SQL usage:

- ✅ **Correct**: Uses T-SQL for querying `sys.procedures` (lines 122-134) - SMO doesn't expose Extended SP metadata efficiently
- ✅ **Correct**: Uses T-SQL system procedures `sp_dropextendedproc` and `sp_addextendedproc` (lines 235, 307) - No SMO equivalent
- ✅ **Correct**: Uses SMO properties `$sourceServer.RootDirectory` (line 181) - Cleaner than querying registry
- ✅ **Correct**: Uses T-SQL `sp_helpextendedproc` (line 254) - System procedure for metadata

This is a good example of the hybrid pattern where T-SQL is used appropriately because:
1. Extended Stored Procedures are a legacy feature with limited SMO support
2. System stored procedures are the documented way to manage them
3. System catalog views provide the metadata SMO doesn't expose

**Anti-Patterns to Avoid:**

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

**Summary:**

- **Default to SMO** for object-oriented operations (Create, Drop, Alter, Script, property access)
- **Use T-SQL** for system views, DMVs, complex queries, system stored procedures, and version-specific logic
- **Combine both** in a hybrid approach when it provides the best balance of functionality and usability
- **Always prefer parameterized queries** when using T-SQL with dynamic values
- **Document your choice** when T-SQL is used instead of SMO for non-obvious reasons

### SPLAT USAGE REQUIREMENT

**USE SPLATS ONLY FOR 3+ PARAMETERS**

- **1-2 parameters**: Use direct parameter syntax
- **3+ parameters**: Use splatted hashtables with `$splat<Purpose>` naming

```powershell
# CORRECT - 2 parameters, direct syntax
$database = Get-DbaDatabase -SqlInstance $instance -Name "master"

# CORRECT - 5 parameters, must use splat
$splatConnection = @{
    SqlInstance     = $instance
    SqlCredential   = $TestConfig.SqlCredential
    Database        = $dbName
    EnableException = $true
    Confirm         = $false
}
$result = New-DbaDatabase @splatConnection

# WRONG - 3+ parameters without splat
Get-DbaDatabase -SqlInstance $instance -Database $db -EnableException $true -WarningAction SilentlyContinue

# WRONG - Using backticks for continuation
Get-DbaDatabase -SqlInstance $instance `
    -Database $db `
    -EnableException $true

# WRONG - Generic $splat without purpose
$splat = @{
    SqlInstance = $instance
    Database    = $db
    Confirm     = $false
}
```

## COMMENT PRESERVATION REQUIREMENT

**ABSOLUTE MANDATE**: ALL COMMENTS MUST BE PRESERVED EXACTLY as they appear in the original code. This includes:
- Development notes and temporary comments
- End-of-file comments
- CI/CD system comments (especially AppVeyor)
- Seemingly unrelated comments
- Any comment that appears to be a note or reminder
- Do not delete anything that says `#$TestConfig.instance...` or similar metadata

**NO EXCEPTIONS** - Every single comment must remain intact in its original location and format.

## STRING AND QUOTE STANDARDS

- **Always use double quotes** for strings (SQL Server module standard)
- Properly escape quotes when needed
- Convert all single quotes to double quotes for string literals
- Remove unnecessary quotes from parameter values

```powershell
# CORRECT
$database = "master"
$query = "SELECT * FROM sys.databases"
$message = "Database `"$dbName`" created successfully"

# WRONG
$database = 'master'
$query = 'SELECT * FROM sys.databases'
```

## HASHTABLE ALIGNMENT (MANDATORY)

**CRITICAL FORMATTING REQUIREMENT**: ALL hashtable assignments must be perfectly aligned using spaces:

```powershell
# REQUIRED FORMAT - Aligned = signs
$splatConnection = @{
    SqlInstance     = $TestConfig.instance2
    SqlCredential   = $TestConfig.SqlCredential
    Database        = $dbName
    EnableException = $true
    Confirm         = $false
}

# FORBIDDEN - Misaligned hashtables
$splat = @{
    SqlInstance = $instance
    Database = $db
    EnableException = $true
}
```

The equals signs must line up vertically to create clean, professional-looking code.

## VARIABLE NAMING CONVENTIONS

- Use `$splat<Purpose>` for 3+ parameters (never plain `$splat`)
- Use direct parameters for 1-2 parameters
- Create unique variable names across all scopes to prevent collisions
- Be descriptive with variable names to indicate their purpose

```powershell
# GOOD - descriptive splat names with aligned formatting
$splatPrimary = @{
    Primary      = $TestConfig.instance3
    Name         = $primaryAgName
    ClusterType  = "None"
    FailoverMode = "Manual"
    Certificate  = "dbatoolsci_AGCert"
    Confirm      = $false
}

$splatReplica = @{
    Secondary = $TestConfig.instance2
    Name      = $replicaAgName
    ClusterType = "None"
    Confirm   = $false
}

# Direct parameters for 1-2 parameters
$ag = Get-DbaLogin -SqlInstance $instance -Login $loginName

# WRONG - Generic splat name
$splat = @{
    Primary = $TestConfig.instance3
    Name    = $agName
}
```

### Unique Names Across Scopes

Use unique, descriptive variable names across scopes to avoid collisions:

```powershell
Describe $CommandName {
    BeforeAll {
        $primaryInstanceName = "instance3"
        $splatPrimary = @{
            SqlInstance = $primaryInstanceName
            Database    = "testdb"
        }
    }

    Context "Specific scenario" {
        BeforeAll {
            # Different variable name - not $primaryInstanceName again
            $secondaryInstanceName = "instance2"
            $splatSecondary = @{
                SqlInstance = $secondaryInstanceName
                Database    = "testdb"
            }
        }
    }
}
```

## ARRAY FORMATTING

Multi-line arrays must be formatted consistently:

```powershell
$expectedParameters = @(
    "SqlInstance",
    "SqlCredential",
    "Database",
    "EnableException"
)

# Multi-line hashtable arrays
$instances = @(
    @{
        Name    = "instance1"
        Version = "2019"
    },
    @{
        Name    = "instance2"
        Version = "2022"
    }
)
```

## WHERE-OBJECT USAGE

Prefer direct property comparison for simple filters:

```powershell
# Preferred - direct property comparison
$master = $databases | Where-Object Name -eq "master"
$systemDbs = $databases | Where-Object Name -in "master", "model", "msdb", "tempdb"

# Required - script block for complex filtering only
$hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
```

## FORMATTING RULES

- Apply OTBS (One True Brace Style) formatting to all code blocks
- No trailing spaces anywhere
- Use `$results.Status.Count` for accurate counting in dbatools context
- Preserve all original parameter names exactly as written
- 4-space indentation for consistency

```powershell
# CORRECT - OTBS style
if ($condition) {
    $result = Get-DbaDatabase -SqlInstance $instance
} else {
    $result = $null
}

# CORRECT - Foreach with OTBS
foreach ($instance in $instances) {
    $splatQuery = @{
        SqlInstance = $instance
        Query       = "SELECT @@VERSION"
    }
    $null = Invoke-DbaQuery @splatQuery
}
```

## TEMPORARY FILES AND RESOURCE MANAGEMENT

- Create temporary test files/directories with unique names using `Get-Random`
- Always clean up temporary resources with `-ErrorAction SilentlyContinue`
- Track all resources created for cleanup

```powershell
BeforeAll {
    # Create unique temp path for this test run
    $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
    $null = New-Item -Path $backupPath -ItemType Directory
    $filesToRemove = @()
}

AfterAll {
    # Always clean up temp files
    Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue
    Remove-Item -Path $filesToRemove -ErrorAction SilentlyContinue
}
```

## DBATOOLS-SPECIFIC CONVENTIONS

### Command Naming and Creation

**CRITICAL RULE**: When creating new commands, follow PowerShell best practices:

1. **Use singular nouns** - Command names must use singular nouns, not plural
   - Correct: `Get-DbaDatabase`, `Get-DbaLogin`, `Get-DbaAgent`
   - Incorrect: `Get-DbaDatabases`, `Get-DbaLogins`, `Get-DbaAgents`

2. **Use approved verbs** - Always use approved PowerShell verbs from the standard set (Get, Set, New, Remove, Invoke, etc.)

3. **Consistent naming pattern** - Follow the `<Verb>-Dba<Noun>` pattern consistently

4. **Follow existing command patterns** - When creating new commands, examine similar existing commands in the `public` folder to understand the standard structure, parameter patterns, and implementation approach

5. **Include Claude as author** - In the `.NOTES` section of the comment-based help, list "Claude" as the author when you create a new command

```powershell
# CORRECT - Singular nouns
function Get-DbaDatabase { }
function Set-DbaLogin { }
function New-DbaAgent { }
function Remove-DbaJob { }

# WRONG - Plural nouns
function Get-DbaDatabases { }
function Set-DbaLogins { }
function New-DbaAgents { }
```

**Example of proper authorship in comment-based help:**

```powershell
function Get-DbaNewFeature {
    <#
    .SYNOPSIS
        Short description of what this command does.

    .DESCRIPTION
        Detailed description of the command's functionality.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Feature, NewCategory
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaNewFeature

    .EXAMPLE
        PS C:\> Get-DbaNewFeature -SqlInstance sql2016

        Description of what this example does.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    # Function implementation
}
```

### Command Registration

**CRITICAL RULE**: When adding a new command, you MUST register it in TWO places:

1. **Add to dbatools.psd1** - In the `FunctionsToExport` array
2. **Add to dbatools.psm1** - In the explicit command export section

Both registrations are required for the command to be properly exported and discoverable.

```powershell
# Example: Adding a new command "Get-DbaNewFeature"

# 1. In dbatools.psd1, add to FunctionsToExport:
FunctionsToExport = @(
    'Get-DbaDatabase'
    'Get-DbaNewFeature'  # ADD HERE
    'Set-DbaDatabase'
    # ... other commands
)

# 2. In dbatools.psm1, add to explicit exports section:
Export-ModuleMember -Function @(
    'Get-DbaDatabase'
    'Get-DbaNewFeature'  # ADD HERE
    'Set-DbaDatabase'
    # ... other commands
)
```

Failure to register in both locations will result in the command not being available when users import the module.

### Commit Messages and Pull Request Naming

**CRITICAL: Always include the `(do ...)` pattern in commit messages** to limit CI test runs to only relevant tests.

**Commit message format:**

```
<CommandName or PrimaryFile> - <Description>

(do CommandName)
```

**Examples:**
```
Get-DbaDatabase - Add support for filtering by recovery model

(do Get-DbaDatabase)
```

```
Set-DbaAgentJobStep - Fix proxy removal and prevent unwanted parameter resets

(do Set-DbaAgentJobStep)
```

```
Sync-DbaLoginPassword - Fix handling of Windows logins

(do Sync-DbaLoginPassword, Get-DbaLogin)
```

```
Login commands - Update authentication handling

(do *Login*)
```

**PR Title Format:**

PR titles should be the same as the first line of the commit message (without the `(do ...)` part):

```
<CommandName or PrimaryFile> - <Description>
```

**Guidelines:**
- Start with the primary command or file affected (PascalCase for commands)
- Use a hyphen and space as separator: ` - `
- Keep the description concise and descriptive (not vague)
- Focus on what the change does, not implementation details
- **ALWAYS include `(do CommandName)` in commit message body to limit test runs**
- For single command changes: Use the command name directly like `(do Sync-DbaLoginPassword)` - wildcard matching is automatic
- For multiple related commands: Use wildcards like `(do *Login*)` or comma-separated `(do *Backup*, *Restore*)`
- Spaces after commas are automatically trimmed
- **RARELY NEEDED**: `=` prefix for exact match `(do =dbatools)` - ONLY use this for infrastructure/CI/test framework changes where you want to run just `dbatools.Tests.ps1` without any related tests. Do NOT use `=` for normal command work.

### Pattern Parameter Convention

**CRITICAL RULE**: When adding a -Pattern parameter to any dbatools command, it MUST use regular expressions (regex), not SQL LIKE wildcards or PowerShell wildcards.

```powershell
# CORRECT - Regex pattern matching
if ($name -match $pattern) { return $true }

# WRONG - SQL LIKE wildcards
$psPattern = $pattern -replace '%', '*' -replace '_', '?'
if ($name -like $psPattern) { return $true }
```

This ensures consistency across all dbatools commands that support pattern matching.

### Parameter Validation Pattern

```powershell
Context "Parameter validation" {
    It "Should have the expected parameters" {
        $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
        $expectedParameters = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "EnableException"
        )
        Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
    }
}
```

### EnableException Handling

For integration tests, use EnableException to ensure test setup/cleanup failures are detected:

```powershell
BeforeAll {
    # Set EnableException for setup to catch failures
    $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

    # Perform setup operations
    $null = New-DbaDatabase -SqlInstance $instance -Name $testDb

    # Remove EnableException for actual test execution
    $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
}

AfterAll {
    # Re-enable for cleanup
    $PSDefaultParameterValues['*-Dba*:EnableException'] = $true
    $null = Remove-DbaDatabase -SqlInstance $instance -Database $testDb
}
```

### Test Management Guidelines

The dbatools test suite must remain manageable in size while ensuring adequate coverage for important functionality. Follow these guidelines:

**When to Add or Update Tests:**
- **ALWAYS update parameter validation tests** when parameters are added or removed from a command
- **ALWAYS add reasonable tests for your changes** - When adding new parameters, features, or fixing bugs, include tests that verify the changes work correctly
- **BE REASONABLE** - Add 1-3 focused tests for your changes, not 100 tests
- **For new commands, ALWAYS create tests** - Refer to `bin/prompts/style.md` and `bin/prompts/pester.md` for test structure and style requirements

**Parameter Validation Updates:**

When you add or remove parameters from a command, you MUST update the parameter validation test:

```powershell
Context "Parameter validation" {
    It "Should have the expected parameters" {
        $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
        $expectedParameters = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "NewParameter",  # ADD new parameters here
            "EnableException"
            # REMOVE deleted parameters from this list
        )
        Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
    }
}
```

**Tests for New Features and Changes:**

When adding new parameters or functionality, include reasonable tests that verify the new feature works. Be focused and practical - test your changes, not everything:

```powershell
# GOOD - Test for a new parameter that filters results
Context "Filter by recovery model" {
    It "Should return only databases with Full recovery model" {
        $splatFilter = @{
            SqlInstance   = $instance
            RecoveryModel = "Full"
        }
        $result = Get-DbaDatabase @splatFilter
        $result.RecoveryModel | Should -All -Be "Full"
    }
}

# GOOD - Test for a new switch parameter
Context "Force parameter" {
    It "Should skip confirmation when -Force is used" {
        $splatForce = @{
            SqlInstance = $instance
            Database    = $testDb
            Force       = $true
            Confirm     = $false
        }
        { Remove-DbaDatabase @splatForce } | Should -Not -Throw
    }
}

# GOOD - Regression test for a specific bug fix
Context "Regression tests" {
    It "Should not remove proxy when updating unrelated job step properties (issue #1234)" {
        # Test for specific bug that was fixed
        $splatUpdate = @{
            SqlInstance = $instance
            Job         = $jobName
            StepName    = $stepName
            Database    = "newdb"
        }
        $result = Set-DbaAgentJobStep @splatUpdate
        $result.ProxyName | Should -Be $originalProxyName
    }
}
```

**Creating Tests for New Commands:**

When creating a new command, you MUST create corresponding tests. Reference these files for detailed guidance:
- **bin/prompts/style.md** - Test style requirements and formatting
- **bin/prompts/pester.md** - Pester v5 structure and migration guidelines

A new command should typically have:
1. Parameter validation test (required)
2. 1-3 integration tests covering core functionality (required)
3. Unit tests if applicable (optional but recommended)

**What Makes a Good Test:**

Good tests are:
- **Focused** - Test one specific behavior or feature
- **Practical** - Test real-world usage scenarios
- **Reasonable** - 1-3 tests per feature, not exhaustive edge cases
- **Relevant** - Test your changes, not unrelated functionality

**Balance is Key:**

Don't add excessive tests, but don't skip tests either. When making changes:
- Fixing a bug? Add a regression test
- Adding a parameter? Add a test that uses it
- Creating a new command? Add parameter validation and 1-3 integration tests
- Refactoring without behavior changes? Existing tests may be sufficient

## VERIFICATION CHECKLIST

**Comment and Parameter Preservation:**
- [ ] All comments preserved exactly as in original
- [ ] Parameter names match original exactly without modification
- [ ] No backticks used for line continuation
- [ ] No `= $true` used in parameter attributes (use modern syntax)
- [ ] Splats used only for 3+ parameters

**Version Compatibility:**
- [ ] No `::new()` syntax used (PowerShell v3+ compatible)
- [ ] No v5+ language features used
- [ ] `New-Object` used for object instantiation
- [ ] SQL Server version support follows project philosophy (support 2000 when feasible)
- [ ] Version requirements documented in parameter help if applicable

**Style Requirements:**
- [ ] Double quotes used for all strings
- [ ] **MANDATORY**: Hashtable assignments perfectly aligned
- [ ] Splat variables use descriptive `$splat<Purpose>` format
- [ ] Variable names are unique across scopes
- [ ] OTBS formatting applied throughout
- [ ] No trailing spaces anywhere

**dbatools Patterns:**
- [ ] SMO used first for object manipulation, scripting, and property access
- [ ] T-SQL only used when appropriate (system views, DMVs, stored procedures, performance, version-specific)
- [ ] EnableException handling correctly implemented
- [ ] Parameter validation follows dbatools pattern
- [ ] Where-Object conversions applied appropriately
- [ ] Temporary resource cleanup implemented properly
- [ ] Splat usage follows 3+ parameter rule strictly

**Command Registration (if adding new commands):**
- [ ] Command name uses singular nouns (not plural)
- [ ] Command uses approved PowerShell verb
- [ ] Command follows `<Verb>-Dba<Noun>` naming pattern
- [ ] Examined similar existing commands for patterns and structure
- [ ] Author listed as "the dbatools team + Claude" in .NOTES section
- [ ] Command added to `FunctionsToExport` in dbatools.psd1
- [ ] Command added to `Export-ModuleMember` in dbatools.psm1

**Test Management:**
- [ ] Parameter validation test updated if parameters were added/removed
- [ ] Reasonable tests (1-3) added for new functionality and parameters
- [ ] Regression tests added for bug fixes
- [ ] New commands include parameter validation and 1-3 integration tests
- [ ] Tests reference bin/prompts/style.md and bin/prompts/pester.md for structure
- [ ] Tests are focused, practical, and relevant to the changes made

## SUMMARY

The golden rules for dbatools code:

1. **NEVER use backticks** - Use splats for 3+ parameters, direct syntax for 1-2
2. **NEVER use `= $true` in parameter attributes** - Use modern syntax: `[Parameter(Mandatory)]` not `[Parameter(Mandatory = $true)]`
3. **NEVER use `::new()` syntax** - Use `New-Object` for PowerShell v3 compatibility
4. **NEVER be dismissive about SQL Server versions** - Support SQL 2000 when feasible, skip gracefully when not
5. **ALWAYS prefer SMO first** - Use T-SQL only when SMO doesn't provide functionality or for better performance/UX
6. **ALWAYS align hashtables** - Equals signs must line up vertically
7. **ALWAYS preserve comments** - Every comment stays exactly as written
8. **ALWAYS use double quotes** - SQL Server module standard
9. **ALWAYS use unique variable names** - Prevent scope collisions
10. **ALWAYS use descriptive splatnames** - `$splatConnection`, not `$splat`
11. **ALWAYS register new commands** - Add to both dbatools.psd1 and dbatools.psm1
