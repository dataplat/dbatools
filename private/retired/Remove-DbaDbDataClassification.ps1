function Remove-DbaDbDataClassification {
    <#
    .SYNOPSIS
        Removes data classification labels from SQL Server table columns

    .DESCRIPTION
        Removes all data classification metadata from table columns by dropping the four extended properties:
        - sys_information_type_id
        - sys_information_type_name
        - sys_sensitivity_label_id
        - sys_sensitivity_label_name

        Accepts piped input from Get-DbaDbDataClassification, making it easy to remove classifications
        from specific columns or bulk-remove classifications across databases.

        Requires SQL Server 2005 or later due to use of sp_dropextendedproperty.

    .PARAMETER InputObject
        Accepts classification objects piped from Get-DbaDbDataClassification.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DataClassification, Classification, Compliance, Security
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2024 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbDataClassification

    .OUTPUTS
        PSCustomObject

        Returns one object per successfully processed column with these properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name
        - Database: The database name
        - Schema: The schema of the table
        - Table: The table name
        - Column: The column name
        - Status: The result of the removal operation

    .EXAMPLE
        PS C:\> Get-DbaDbDataClassification -SqlInstance sql2019 -Database AdventureWorks | Remove-DbaDbDataClassification

        Removes all data classifications from the AdventureWorks database.

    .EXAMPLE
        PS C:\> Get-DbaDbDataClassification -SqlInstance sql2019 -Database AdventureWorks -Table Customer | Remove-DbaDbDataClassification -Confirm:$false

        Removes data classifications from all classified columns in the Customer table without prompting.

    .EXAMPLE
        PS C:\> Get-DbaDbDataClassification -SqlInstance sql2019 -Database AdventureWorks | Where-Object SensitivityLabel -eq "General" | Remove-DbaDbDataClassification

        Removes only classifications with the "General" sensitivity label from AdventureWorks.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [parameter(ValueFromPipeline, Mandatory)]
        [psobject[]]$InputObject,
        [switch]$EnableException
    )
    process {
        foreach ($classObj in $InputObject) {
            $db = $classObj.DatabaseObject
            if (-not $db) {
                Stop-Function -Message "No database object found in input. Use Get-DbaDbDataClassification to get valid input objects." -Continue
                continue
            }

            $server = $db.Parent
            $schemaName = $classObj.Schema
            $tableName = $classObj.Table
            $columnName = $classObj.Column
            $target = "[$schemaName].[$tableName].[$columnName] in $($db.Name) on $server"

            if ($Pscmdlet.ShouldProcess($target, "Removing data classification")) {
                $escapedSchema = $schemaName.Replace("'", "''")
                $escapedTable = $tableName.Replace("'", "''")
                $escapedColumn = $columnName.Replace("'", "''")

                $status = "Removed"
                $errors = @()

                foreach ($propName in "sys_information_type_id", "sys_information_type_name", "sys_sensitivity_label_id", "sys_sensitivity_label_name") {
                    $checkSql = "
SELECT COUNT(1) AS PropExists
FROM sys.extended_properties ep
INNER JOIN sys.objects o ON ep.major_id = o.object_id
INNER JOIN sys.columns c ON o.object_id = c.object_id AND ep.minor_id = c.column_id
WHERE SCHEMA_NAME(o.schema_id) = '$escapedSchema'
  AND o.name = '$escapedTable'
  AND c.name = '$escapedColumn'
  AND ep.name = '$propName'
  AND ep.class = 1"

                    try {
                        $exists = $db.Query($checkSql).PropExists
                        if ($exists -gt 0) {
                            $dropSql = "EXEC sys.sp_dropextendedproperty @name = N'$propName', @level0type = N'SCHEMA', @level0name = N'$escapedSchema', @level1type = N'TABLE', @level1name = N'$escapedTable', @level2type = N'COLUMN', @level2name = N'$escapedColumn'"
                            $db.Query($dropSql)
                        }
                    } catch {
                        $errors += $propName
                        Write-Message -Level Warning -Message "Failed to drop extended property '$propName' from $target : $_"
                    }
                }

                if ($errors.Count -gt 0) {
                    $status = "Partial - failed to remove: $($errors -join ', ')"
                }

                [PSCustomObject]@{
                    ComputerName = $classObj.ComputerName
                    InstanceName = $classObj.InstanceName
                    SqlInstance  = $classObj.SqlInstance
                    Database     = $classObj.Database
                    Schema       = $schemaName
                    Table        = $tableName
                    Column       = $columnName
                    Status       = $status
                }
            }
        }
    }
}
