function Remove-DbaDbTable {
    <#
    .SYNOPSIS
        Removes a database table(s) from each database and SQL Server instance.

    .DESCRIPTION
        Removes a database table(s), with supported piping from Get-DbaDbTable.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The target database(s).

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto populated from the server.

    .PARAMETER IncludeSystemDBs
        If this switch is enabled, tables can be removed from system databases.

    .PARAMETER IncludeSystemDBs
        If this switch is enabled, tables can be removed from system databases.

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
        Author: Mikey Bronowski (@MikeyBronowski), https://bronowski.it

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbTable

    .EXAMPLE
        PS C:\> Remove-DbaDbTable -SqlInstance localhost, sql2016 -Database db1, db2 -Table udf1, udf2, udf3

        Removes udf1, udf2, udf3 from db1 and db2 on the local and sql2016 SQL Server instances.

    .EXAMPLE
        PS C:\> $udfs = Get-DbaDbTable -SqlInstance localhost, sql2016 -Database db1, db2 -Table udf1, udf2, udf3
        PS C:\> $udfs | Remove-DbaDbTable

        Removes udf1, udf2, udf3 from db1 and db2 on the local and sql2016 SQL Server instances.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(ParameterSetName = 'NonPipeline', Mandatory = $true, Position = 0)]
        [DbaInstanceParameter[]]$SqlInstance,
        #[Parameter(ParameterSetName = 'NonPipeline')]
        [PSCredential]$SqlCredential,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [string[]]$Database,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [string[]]$ExcludeDatabase,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [switch]$IncludeSystemDBs,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [string[]]$Table,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Table[]]$InputObject,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [switch]$EnableException
    )

    begin {
        $udfs = @( )
    }

    process {
        if ($SqlInstance) {
            $params = $PSBoundParameters
            $null = $params.Remove('WhatIf')
            $null = $params.Remove('Confirm')
            $udfs = Get-DbaDbTable @params
        } else {
            $udfs += $InputObject
        }
    }

    end {
        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaDbTable.
        foreach ($udfItem in $udfs) {
            if ($PSCmdlet.ShouldProcess($udfItem.Parent.Parent.Name, "Removing the table $($udfItem.Schema).$($udfItem.Name) in the database $($udfItem.Parent.Name) on $($udfItem.Parent.Parent.Name)")) {
                $output = [pscustomobject]@{
                    ComputerName = $udfItem.Parent.Parent.ComputerName
                    InstanceName = $udfItem.Parent.Parent.ServiceName
                    SqlInstance  = $udfItem.Parent.Parent.DomainInstanceName
                    Database     = $udfItem.Parent.Name
                    Table          = "$($udfItem.Schema).$($udfItem.Name)"
                    udfName      = $udfItem.Name
                    udfSchema    = $udfItem.Schema
                    Status       = $null
                    IsRemoved    = $false
                }
                try {
                    $udfItem.Drop()
                    $output.Status = "Dropped"
                    $output.IsRemoved = $true
                } catch {
                    Stop-Function -Message "Failed removing the table $($udfItem.Schema).$($udfItem.Name) in the database $($udfItem.Parent.Name) on $($udfItem.Parent.Parent.Name)" -ErrorRecord $_
                    $output.Status = (Get-ErrorMessage -Record $_)
                    $output.IsRemoved = $false
                }
                $output
            }
        }
    }
}