function Remove-DbaDbTable {
    <#
    .SYNOPSIS
        Drops tables from SQL Server databases with safety controls and detailed status reporting.

    .DESCRIPTION
        Permanently removes tables from one or more databases using SQL Server Management Objects (SMO). This function provides a safer alternative to manual DROP TABLE statements by including built-in confirmation prompts and comprehensive error handling. You can specify tables directly by name or pipe table objects from Get-DbaDbTable for more complex filtering scenarios. Each removal operation returns detailed status information including success confirmation and specific error messages when failures occur.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to target for table removal operations. Accepts multiple database names as an array.
        Use this when you need to remove tables from specific databases rather than searching across all databases on the instance.

    .PARAMETER Table
        Specifies the names of tables to remove from the target databases. Accepts multiple table names as an array.
        Tables should be specified by name only (without schema prefix) as the function will find tables regardless of schema. Use Get-DbaDbTable for more complex filtering scenarios.

    .PARAMETER InputObject
        Accepts table objects directly from Get-DbaDbTable for removal operations. This approach allows for advanced filtering and validation before deletion.
        Use this parameter when you need to remove tables based on complex criteria like size, row count, or schema patterns that Get-DbaDbTable can filter.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.
        This is the default. Use -Confirm:$false to suppress these prompts.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Table, Database
        Author: Andreas Jordan (@JordanOrdix), ordix.de

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbTable

    .EXAMPLE
        PS C:\> Remove-DbaDbTable -SqlInstance localhost, sql2016 -Database db1, db2 -Table table1, table2, table3

        Removes table1, table2, table3 from db1 and db2 on the local and sql2016 SQL Server instances.

    .EXAMPLE
        PS C:\> $tables = Get-DbaDbTable -SqlInstance localhost, sql2016 -Database db1, db2 -Table table1, table2, table3
        PS C:\> $tables | Remove-DbaDbTable

        Removes table1, table2, table3 from db1 and db2 on the local and sql2016 SQL Server instances.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High", DefaultParameterSetName = "Default")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Table,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Table[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        $tables = @( )
    }

    process {
        if (-not $PSBoundParameters.SqlInstance -and -not $PSBoundParameters.InputObject) {
            Stop-Function -Message "You must specify either SqlInstance or InputObject"
            return
        }
        if ($SqlInstance) {
            $params = $PSBoundParameters
            $null = $params.Remove('WhatIf')
            $null = $params.Remove('Confirm')
            $tables = Get-DbaDbTable @params
        } else {
            $tables += $InputObject
        }
    }

    end {
        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaDbTable.
        foreach ($tableItem in $tables) {
            if ($PSCmdlet.ShouldProcess($tableItem.Parent.Parent.Name, "Removing the table $($tableItem.Schema).$($tableItem.Name) in the database $($tableItem.Parent.Name) on $($tableItem.Parent.Parent.Name)")) {
                $output = [PSCustomObject]@{
                    ComputerName = $tableItem.Parent.Parent.ComputerName
                    InstanceName = $tableItem.Parent.Parent.ServiceName
                    SqlInstance  = $tableItem.Parent.Parent.DomainInstanceName
                    Database     = $tableItem.Parent.Name
                    Table        = "$($tableItem.Schema).$($tableItem.Name)"
                    TableName    = $tableItem.Name
                    TableSchema  = $tableItem.Schema
                    Status       = $null
                    IsRemoved    = $false
                }
                try {
                    $tableItem.Drop()
                    $output.Status = "Dropped"
                    $output.IsRemoved = $true
                } catch {
                    Stop-Function -Message "Failed removing the view $($tableItem.Schema).$($tableItem.Name) in the database $($tableItem.Parent.Name) on $($tableItem.Parent.Parent.Name)" -ErrorRecord $_
                    $output.Status = (Get-ErrorMessage -Record $_)
                    $output.IsRemoved = $false
                }
                $output
            }
        }
    }
}