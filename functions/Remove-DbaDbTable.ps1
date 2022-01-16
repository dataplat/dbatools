function Remove-DbaDbTable {
    <#
    .SYNOPSIS
        Removes database table(s) from each database and SQL Server instance.

    .DESCRIPTION
        Removes database table(s), with supported piping from Get-DbaDbTable.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The target database(s).

    .PARAMETER Table
        The name(s) of the table(s).

    .PARAMETER InputObject
        Allows piping from Get-DbaDbTable.

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
                $output = [pscustomobject]@{
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