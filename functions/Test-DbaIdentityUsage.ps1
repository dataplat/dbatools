function Test-DbaIdentityUsage {
    <#
    .SYNOPSIS
        Displays information relating to IDENTITY seed usage.  Works on SQL Server 2008 and above.

    .DESCRIPTION
        IDENTITY seeds have max values based off of their data type.  This module will locate identity columns and report the seed usage.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER Threshold
        Allows you to specify a minimum % of the seed range being utilized.  This can be used to ignore seeds that have only utilized a small fraction of the range.

    .PARAMETER ExcludeSystem
        Allows you to suppress output on system databases

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Identity, Table, Column
        Author: Brandon Abshire, netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaIdentityUsage

    .EXAMPLE
        PS C:\> Test-DbaIdentityUsage -SqlInstance sql2008, sqlserver2012

        Check identity seeds for servers sql2008 and sqlserver2012.

    .EXAMPLE
        PS C:\> Test-DbaIdentityUsage -SqlInstance sql2008 -Database TestDB

        Check identity seeds on server sql2008 for only the TestDB database

    .EXAMPLE
        PS C:\> Test-DbaIdentityUsage -SqlInstance sql2008 -Database TestDB -Threshold 20

        Check identity seeds on server sql2008 for only the TestDB database, limiting results to 20% utilization of seed range or higher

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [int]$Threshold = 0,
        [switch]$ExcludeSystem,
        [switch]$EnableException
    )

    begin {
        $sql = ";WITH CT_DT AS
        (
            SELECT 'tinyint' AS DataType, 0 AS MinValue ,255 AS MaxValue UNION
            SELECT 'smallint' AS DataType, -32768 AS MinValue ,32767 AS MaxValue UNION
            SELECT 'int' AS DataType, -2147483648 AS MinValue ,2147483647 AS MaxValue UNION
            SELECT 'bigint' AS DataType, -9223372036854775808 AS MinValue ,9223372036854775807 AS MaxValue
        ), CTE_1
        AS
        (
          SELECT SCHEMA_NAME(o.schema_id) AS SchemaName,
                 OBJECT_NAME(a.Object_id) as TableName,
                 a.Name as ColumnName,
                 seed_value AS SeedValue,
                 CONVERT(bigint, increment_value) as IncrementValue,

                 CONVERT(bigint, ISNULL(a.last_value, seed_value)) AS LastValue,

                 (CASE
                        WHEN CONVERT(bigint, increment_value) < 0 THEN
                            (CONVERT(bigint, seed_value)
                            - CONVERT(bigint, ISNULL(last_value, seed_value))
                            + (CASE WHEN CONVERT(bigint, seed_value) <> 0 THEN ABS(CONVERT(bigint, increment_value)) ELSE 0 END))
                        ELSE
                            (CONVERT(bigint, ISNULL(last_value, seed_value))
                            - CONVERT(bigint, seed_value)
                            + (CASE WHEN CONVERT(bigint, seed_value) <> 0 THEN ABS(CONVERT(bigint, increment_value)) ELSE 0 END))
                    END) / ABS(CONVERT(bigint, increment_value))  AS NumberOfUses,

                  CAST (
                        (CASE
                            WHEN CONVERT(Numeric(20, 0), increment_value) < 0 THEN
                                ABS(CONVERT(Numeric(20, 0),dt.MinValue)
                                - CONVERT(Numeric(20, 0), seed_value)
                                - (CASE WHEN CONVERT(Numeric(20, 0), seed_value) <> 0 THEN ABS(CONVERT(Numeric(20, 0), increment_value)) ELSE 0 END))
                            ELSE
                                CONVERT(Numeric(20, 0),dt.MaxValue)
                                - CONVERT(Numeric(20, 0), seed_value)
                                + (CASE WHEN CONVERT(Numeric(20, 0), seed_value) <> 0 THEN ABS(CONVERT(Numeric(20, 0), increment_value)) ELSE 0 END)
                        END) / ABS(CONVERT(Numeric(20, 0), increment_value))
                    AS Numeric(20, 0)) AS MaxNumberRows

            FROM sys.identity_columns a
                INNER JOIN sys.objects o
                   ON a.object_id = o.object_id
                INNER JOIN sys.types As b
                     ON a.system_type_id = b.system_type_id
                INNER JOIN CT_DT dt
                     ON b.name = dt.DataType
          WHERE a.seed_value is not null
        ),
        CTE_2
        AS
        (
        SELECT SchemaName, TableName, ColumnName, CONVERT(BIGINT, SeedValue) AS SeedValue, CONVERT(BIGINT, IncrementValue) AS IncrementValue, LastValue, ABS(CONVERT(NUMERIC(20,0),MaxNumberRows)) AS MaxNumberRows, NumberOfUses,
               CONVERT(NUMERIC(18, 2), ((CONVERT(FLOAT, NumberOfUses) / ABS(CONVERT(NUMERIC(20, 0), NULLIF(MaxNumberRows,0))) * 100))) AS [PercentUsed]
          FROM CTE_1
        )
        SELECT DB_NAME() as DatabaseName, SchemaName, TableName, ColumnName, SeedValue, IncrementValue, LastValue, MaxNumberRows, NumberOfUses, [PercentUsed]
          FROM CTE_2"

        if ($Threshold -gt 0) {
            $sql += " WHERE [PercentUsed] >= " + $Threshold + " ORDER BY [PercentUsed] DESC"
        } else {
            $sql += " ORDER BY [PercentUsed] DESC"
        }
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $dbs = $server.Databases

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            if ($ExcludeSystem) {
                $dbs = $dbs | Where-Object IsSystemObject -EQ $false
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $db on $instance"

                if ($db.IsAccessible -eq $false) {
                    Stop-Function -Message "The database $db is not accessible. Skipping." -Continue
                }

                try {
                    $results = $db.Query($sql)
                } catch {
                    Stop-Function -Message "Error capturing data on $db" -Target $instance -ErrorRecord $_ -Exception $_.Exception -Continue
                }

                foreach ($row in $results) {
                    if ($row.PercentUsed -eq [System.DBNull]::Value) {
                        continue
                    }

                    if ($row.PercentUsed -ge $threshold) {
                        [PSCustomObject]@{
                            ComputerName   = $server.ComputerName
                            InstanceName   = $server.ServiceName
                            SqlInstance    = $server.DomainInstanceName
                            Database       = $row.DatabaseName
                            Schema         = $row.SchemaName
                            Table          = $row.TableName
                            Column         = $row.ColumnName
                            SeedValue      = $row.SeedValue
                            IncrementValue = $row.IncrementValue
                            LastValue      = $row.LastValue
                            MaxNumberRows  = $row.MaxNumberRows
                            NumberOfUses   = $row.NumberOfUses
                            PercentUsed    = $row.PercentUsed
                        } | Select-DefaultView -Exclude MaxNumberRows, NumberOfUses
                    }
                }
            }
        }
    }
}