function Remove-DbaDbCheckConstraint {
    <#
    .SYNOPSIS
        Removes check constraints from SQL Server database tables

    .DESCRIPTION
        Removes check constraints from database tables across one or more SQL Server instances. Check constraints enforce data integrity by validating that column values meet specific criteria before allowing INSERT or UPDATE operations.

        This function is useful when modifying table schemas, removing outdated business rules, or preparing databases for data migration where existing constraints might block bulk operations. You can target specific databases or remove constraints across multiple instances simultaneously.

        Supports piping from Get-DbaDbCheckConstraint to remove only specific constraints that match your criteria, such as constraints containing particular patterns or on specific tables.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to target for check constraint removal. Accepts wildcards and arrays for multiple databases.
        Use this when you need to remove constraints from specific databases rather than all databases on the instance.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from check constraint removal operations. Accepts wildcards and arrays for multiple databases.
        Use this to protect critical databases like master, msdb, or production databases when running against multiple instances.

    .PARAMETER ExcludeSystemTable
        Excludes check constraints on system tables from the removal operation, focusing only on user-created tables.
        Use this switch when you want to modify only business logic constraints while preserving SQL Server's built-in constraints.

    .PARAMETER InputObject
        Accepts check constraint objects from Get-DbaDbCheckConstraint for targeted removal operations.
        Use this to remove only specific constraints that match your filtering criteria, such as constraints with certain patterns or on particular tables.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.
        This is the default. Use -Confirm:$false to suppress these prompts.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Returns one object per check constraint processed, with details about the removal operation result.

        Properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The database where the check constraint was located
        - Name: The name of the check constraint
        - Status: The result of the removal operation - either "Dropped" if successful, or an error message if the operation failed
        - IsRemoved: Boolean indicating whether the check constraint was successfully removed (true) or failed (false)

    .NOTES
        Tags: Check, Constraint, Database
        Author: Mikey Bronowski (@MikeyBronowski), bronowski.it

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbCheckConstraint

    .EXAMPLE
        PS C:\> Remove-DbaDbCheckConstraint -SqlInstance localhost, sql2016 -Database db1, db2

        Removes all check constraints from db1 and db2 on the local and sql2016 SQL Server instances.

    .EXAMPLE
        PS C:\> $chkcs = Get-DbaDbCheckConstraint -SqlInstance localhost, sql2016 -Database db1, db2
        PS C:\> $chkcs | Remove-DbaDbCheckConstraint

        Removes all check constraints from db1 and db2 on the local and sql2016 SQL Server instances.

    .EXAMPLE
        PS C:\> Remove-DbaDbCheckConstraint -SqlInstance localhost, sql2016 -Database db1, db2 -ExcludeSystemTable

        Removes all check constraints except those in system tables from db1 and db2 on the local and sql2016 SQL Server instances.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Default', ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$ExcludeSystemTable,
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Check[]]$InputObject,
        [Parameter(ParameterSetName = 'Pipeline')]
        [switch]$EnableException
    )

    begin {
        $chkcs = @( )
    }

    process {
        if ($SqlInstance) {
            $params = $PSBoundParameters
            $null = $params.Remove('WhatIf')
            $null = $params.Remove('Confirm')
            $chkcs = Get-DbaDbCheckConstraint @params
        } else {
            $chkcs += $InputObject
        }
    }

    end {
        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaDbUdf.
        foreach ($chkcItem in $chkcs) {
            if ($PSCmdlet.ShouldProcess($chkcItem.Parent.Parent.Parent.Name, "Removing the check constraint [$($chkcItem.Name)] on the table $($chkcItem.Parent) on the database [$($chkcItem.Parent.Parent.Name)]")) {
                $output = [PSCustomObject]@{
                    ComputerName = $chkcItem.ComputerName
                    InstanceName = $chkcItem.Parent.Parent.Parent.ServiceName
                    SqlInstance  = $chkcItem.Parent.Parent.Parent.DomainInstanceName
                    Database     = $chkcItem.Parent.Name
                    Name         = $chkcItem.Name
                    Status       = $null
                    IsRemoved    = $false
                }
                try {
                    $chkcItem.Drop()
                    $output.Status = "Dropped"
                    $output.IsRemoved = $true
                } catch {
                    Stop-Function -Message "Failed removing the check constraint $($chkcItem.Schema).$($chkcItem.Name) in the database $($chkcItem.Parent.Name) on $($chkcItem.Parent.Parent.Name)" -ErrorRecord $_
                    $output.Status = (Get-ErrorMessage -Record $_)
                    $output.IsRemoved = $false
                }
                $output
            }
        }
    }
}