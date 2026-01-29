# Command Specification: Get-DbaIndexFragmentation

## Overview

**Command Name**: `Get-DbaIndexFragmentation`
**Author**: the dbatools team + Claude
**Category**: Index

### Purpose
Retrieves index fragmentation statistics for databases, providing DBAs with critical information for index maintenance planning. This command queries `sys.dm_db_index_physical_stats` to return fragmentation percentages, page counts, and recommendations.

### User Stories

- As a DBA, I want to quickly identify fragmented indexes so that I can schedule maintenance
- As a DBA, I want to filter by fragmentation threshold so that I focus on problematic indexes
- As a developer, I want to pipe database objects to check their indexes

---

## Requirements

### Functional Requirements

1. **Core Functionality**
   - [x] Query index fragmentation from sys.dm_db_index_physical_stats
   - [x] Return fragmentation percentage, page count, index type
   - [x] Support filtering by minimum fragmentation threshold
   - [x] Support filtering by specific database(s)

2. **Input Handling**
   - [x] Accept SqlInstance parameter (single or array)
   - [x] Support pipeline input from `Get-DbaDatabase`
   - [x] Handle SqlCredential for authentication
   - [x] Accept Database parameter for filtering

3. **Output**
   - [x] Emit objects immediately to pipeline (no collection)
   - [x] Include standard properties: ComputerName, InstanceName, SqlInstance
   - [x] Custom type name: `Sqlcollaborative.Dbatools.IndexFragmentation`

### Non-Functional Requirements

- **SQL Server Compatibility**: Minimum version SQL Server 2005 (DMV not available in 2000)
- **PowerShell Compatibility**: PowerShell v3+
- **Performance**: Should handle databases with thousands of indexes efficiently

---

## Technical Design

### Approach

- [x] Use T-SQL for: Querying sys.dm_db_index_physical_stats DMV
- [x] Use SMO for: Database enumeration and connection management

T-SQL is appropriate here because:
1. `sys.dm_db_index_physical_stats` is a DMV with no SMO equivalent
2. Need to join with sys.indexes and sys.objects for names
3. Performance-critical operation benefits from server-side filtering

### Similar Commands

- `Get-DbaDbIndex` - Similar pattern for index enumeration
- `Get-DbaDbSpace` - Reference for DMV-based queries with database filtering

### Parameters

| Parameter | Type | Mandatory | Pipeline | Description |
|-----------|------|-----------|----------|-------------|
| SqlInstance | DbaInstanceParameter[] | Yes* | No | Target SQL Server instance(s) |
| SqlCredential | PSCredential | No | No | SQL Server authentication credential |
| Database | String[] | No | No | Filter to specific database(s) |
| ExcludeDatabase | String[] | No | No | Databases to exclude |
| MinimumFragmentation | Int | No | No | Only return indexes with fragmentation >= this value (default: 0) |
| MinimumPageCount | Int | No | No | Only return indexes with page count >= this value (default: 1000) |
| InputObject | Database[] | No | Yes | Pipeline input from Get-DbaDatabase |
| EnableException | Switch | No | No | Throw terminating errors |

*SqlInstance is mandatory unless InputObject is provided via pipeline

### Output Object

```powershell
[PSCustomObject]@{
    ComputerName              = $server.ComputerName
    InstanceName              = $server.ServiceName
    SqlInstance               = $server.DomainInstanceName
    DatabaseName              = $db.Name
    SchemaName                = $row.SchemaName
    TableName                 = $row.TableName
    IndexName                 = $row.IndexName
    IndexType                 = $row.IndexType
    FragmentationPercent      = $row.avg_fragmentation_in_percent
    PageCount                 = $row.page_count
    Recommendation            = $recommendation  # "None", "Reorganize", "Rebuild"
}
```

---

## Test Scenarios

### Unit Tests

1. **Parameter Validation**
   - Test: SqlInstance is mandatory when no pipeline input
   - Test: MinimumFragmentation accepts integer values
   - Test: Database accepts string array

2. **Recommendation Logic**
   - Test: < 10% fragmentation = "None"
   - Test: 10-30% fragmentation = "Reorganize"
   - Test: > 30% fragmentation = "Rebuild"

### Integration Tests

1. **Single Instance**
   - Test against: `$TestConfig.instance1`
   - Expected: Returns index fragmentation for all databases

2. **Database Filter**
   - Test against: `$TestConfig.instance1` with `-Database master`
   - Expected: Returns only master database indexes

3. **Pipeline Input**
   - Test: `Get-DbaDatabase -SqlInstance $instance -Database master | Get-DbaIndexFragmentation`
   - Expected: Returns master database indexes

4. **Fragmentation Threshold**
   - Test: `-MinimumFragmentation 30`
   - Expected: Only highly fragmented indexes returned

---

## Edge Cases and Error Handling

| Scenario | Expected Behavior |
|----------|-------------------|
| SQL Server 2000 | Skip with warning (DMV requires SQL 2005+) |
| Database offline | Skip database with warning |
| No indexes found | Return nothing (no error) |
| Permission denied to DMV | Write warning with database name |
| Heap (no clustered index) | Include with IndexType "Heap" |

---

## Implementation Notes

### Files to Create/Modify

1. `public/Get-DbaIndexFragmentation.ps1` - Main command implementation
2. `tests/Get-DbaIndexFragmentation.Tests.ps1` - Pester v5 tests
3. `dbatools.psd1` - Add to FunctionsToExport
4. `dbatools.psm1` - Add to Export-ModuleMember

### Dependencies

- Existing dbatools functions: `Connect-DbaInstance`, `Get-DbaDatabase`, `Stop-Function`
- T-SQL: `sys.dm_db_index_physical_stats`, `sys.indexes`, `sys.objects`, `sys.schemas`

### T-SQL Query

```sql
SELECT
    s.name AS SchemaName,
    o.name AS TableName,
    i.name AS IndexName,
    i.type_desc AS IndexType,
    ps.avg_fragmentation_in_percent,
    ps.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ps
INNER JOIN sys.indexes i ON ps.object_id = i.object_id AND ps.index_id = i.index_id
INNER JOIN sys.objects o ON i.object_id = o.object_id
INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.type = 'U'  -- User tables only
    AND ps.avg_fragmentation_in_percent >= @MinimumFragmentation
    AND ps.page_count >= @MinimumPageCount
ORDER BY ps.avg_fragmentation_in_percent DESC
```

### Code Pattern Reference

```powershell
foreach ($instance in $SqlInstance) {
    try {
        $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
    } catch {
        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $instance -Continue
    }

    $databases = $server.Databases | Where-Object { $_.IsAccessible }

    if ($Database) {
        $databases = $databases | Where-Object Name -In $Database
    }

    foreach ($db in $databases) {
        $splatQuery = @{
            SqlInstance = $server
            Database    = $db.Name
            Query       = $query
        }
        $results = Invoke-DbaQuery @splatQuery

        foreach ($row in $results) {
            # Emit immediately
            [PSCustomObject]@{
                ComputerName         = $server.ComputerName
                # ... properties
            }
        }
    }
}
```

---

## Acceptance Criteria

- [x] Command follows dbatools naming conventions
- [x] All parameters use proper types (no `= $true` syntax)
- [x] Uses splatting for 3+ parameter calls
- [x] Emits objects immediately to pipeline
- [x] Includes proper help documentation
- [x] Has Pester v5 tests
- [x] Registered in both dbatools.psd1 and dbatools.psm1
- [x] Requires SQL Server 2005+ (DMV limitation)
- [x] No backticks for line continuation
- [x] Hashtables are properly aligned
- [x] Recommendation logic is correct (None/Reorganize/Rebuild)
