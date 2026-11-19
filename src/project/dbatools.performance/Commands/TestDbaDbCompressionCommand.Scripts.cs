#nullable enable

namespace Dataplat.Dbatools.Commands;

// Hop script constants (the verbatim retired PS bodies) - split per the repo 400-line file limit.
public sealed partial class TestDbaDbCompressionCommand
{

    private const string BeginCarrierMarker = "__dbatoolsTdcBeginCarrier";
    private const string ProcessCarrierMarker = "__dbatoolsTdcProcessCarrier";

    private const string BeginScript = """
param($Schema, $Table, $ResultSize, $Rank, $FilterBy, $__boundParameterNames, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($Schema, $Table, $ResultSize, $Rank, $FilterBy, $__boundParameterNames, $EnableException)
    Write-Message -Level System -Message "Bound parameters: $($__boundParameterNames -join ", ")" -FunctionName Test-DbaDbCompression -ModuleName "dbatools"

        if ($Schema) {
            $schemaNames = $Schema | ForEach-Object { $_.Replace("'", "''") }
            $sqlSchemaWhere = "AND s.name IN (N'$($schemaNames -join "','")')"
        }

        if ($Table) {
            $tableParts = $Table | ForEach-Object { Get-ObjectNameParts -ObjectName $_ }
            $tableWhereClauses = foreach ($tablePart in $tableParts) {
                $tableName = ([string]$tablePart.Name).Replace("'", "''")
                $clauseParts = @("t.name = N'$tableName'")

                if ($tablePart.Schema) {
                    $schemaName = ([string]$tablePart.Schema).Replace("'", "''")
                    $clauseParts += "s.name = N'$schemaName'"
                }

                if ($tablePart.Database) {
                    $databaseName = ([string]$tablePart.Database).Replace("'", "''")
                    $clauseParts += "DB_NAME() = N'$databaseName'"
                }

                "($($clauseParts -join " AND "))"
            }

            $sqlTableWhere = "AND ($($tableWhereClauses -join " OR "))"
        }

        if ($ResultSize) {
            $sqlOrderBy = switch ($Rank) {
                UsedPages { 'UsedSpaceKB' }
                TotalRows { 'RowCounts' }
                default { 'TotalSpaceKB' }
            }

            if ($FilterBy -eq 'Table') {
                $sqlJoinFiltered = 'AND t.TableName = tdc.TableName COLLATE DATABASE_DEFAULT'
                $indexSQL = '0 as [IndexID]'
                $partitionSQL = '0 AS [Partition]'
                $groupBySQL = 's.Name, t.Name'
            } elseif ($FilterBy -eq 'Index') {
                $sqlJoinFiltered = 'AND t.TableName = tdc.TableName COLLATE DATABASE_DEFAULT AND t.IndexID = tdc.IndexID'
                $indexSQL = 'i.index_id as [IndexID]'
                $partitionSQL = '0 AS [Partition]'
                $groupBySQL = 's.Name, t.Name, i.index_id'
            } else {
                $sqlJoinFiltered = 'AND t.TableName = tdc.TableName COLLATE DATABASE_DEFAULT AND t.IndexID = tdc.IndexID AND t.[Partition] = tdc.[Partition]'
                $indexSQL = 'i.index_id as [IndexID]'
                $partitionSQL = 'p.partition_number AS [Partition]'
                $groupBySQL = 's.Name, t.Name, i.index_id, p.partition_number'
            }

            $sqlRestrict = "-- remove tables not in Top N
                With TopN(SchemaName, TableName, IndexID, [Partition], RowCounts, TotalSpaceKB, UsedSpaceKB) as
                (
                    SELECT TOP $ResultSize
                        s.name AS SchemaName,
                        t.name AS TableName,
                        $indexSQL,
                        $partitionSQL,
                        SUM(p.rows) AS RowCounts,
                        SUM(a.total_pages) * 8 AS TotalSpaceKB,
                        SUM(a.used_pages) * 8 AS UsedSpaceKB
                    FROM
                        sys.tables t
                    INNER JOIN
                        sys.indexes i ON t.object_id = i.object_id
                    INNER JOIN
                        sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
                    INNER JOIN
                        sys.allocation_units a ON p.partition_id = a.container_id
                    LEFT OUTER JOIN
                        sys.schemas s ON t.schema_id = s.schema_id
                    WHERE OBJECTPROPERTY(t.object_id, 'IsUserTable') = 1
                        AND p.data_compression_desc = 'NONE'
                        $sqlSchemaWhere
                        $sqlTableWhere
                    GROUP BY
                        $groupBySQL
                    ORDER BY
                        $sqlOrderBy DESC
                )
                DELETE tdc
                FROM ##TestDbaCompression tdc
                LEFT JOIN TopN t
                    ON t.SchemaName = tdc.[Schema] COLLATE DATABASE_DEFAULT
                    $sqlJoinFiltered
                WHERE t.IndexID IS NULL;"
        }

    [pscustomobject]@{
        __dbatoolsTdcBeginCarrier = $true
        SqlSchemaWhere = $sqlSchemaWhere
        SqlTableWhere = $sqlTableWhere
        SqlRestrict = $sqlRestrict
    }
} $Schema $Table $ResultSize $Rank $FilterBy $__boundParameterNames $EnableException @__commonParameters 3>&1 2>&1
""";
}
