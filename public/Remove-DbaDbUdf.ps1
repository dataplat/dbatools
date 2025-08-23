function Remove-DbaDbUdf {
    <#
    .SYNOPSIS
        Removes user-defined functions from SQL Server databases.

    .DESCRIPTION
        Removes user-defined functions from specified databases, providing a clean way to drop obsolete or unwanted UDFs without manual T-SQL scripting. This function is particularly useful during database cleanup operations, code refactoring projects, or when removing deprecated functions that are no longer needed. Supports filtering by schema and function name, and can exclude system UDFs to prevent accidental removal of built-in functions. Works seamlessly with Get-DbaDbUdf for pipeline operations.

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

    .PARAMETER ExcludeSystemUdf
        This switch removes all system objects from the UDF collection.

    .PARAMETER Schema
        The schema(s) to process. If unspecified, all schemas will be processed.

    .PARAMETER ExcludeSchema
        The schema(s) to exclude.

    .PARAMETER Name
        The name(s) of the user defined functions to process. If unspecified, all user defined functions will be processed.

    .PARAMETER ExcludeName
        The name(s) of the user defined functions to exclude.

    .PARAMETER InputObject
        Allows piping from Get-DbaDbUdf.

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
        Tags: Udf, Database
        Author: Mikey Bronowski (@MikeyBronowski), bronowski.it

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbUdf

    .EXAMPLE
        PS C:\> Remove-DbaDbUdf -SqlInstance localhost, sql2016 -Database db1, db2 -Name udf1, udf2, udf3

        Removes udf1, udf2, udf3 from db1 and db2 on the local and sql2016 SQL Server instances.

    .EXAMPLE
        PS C:\> $udfs = Get-DbaDbUdf -SqlInstance localhost, sql2016 -Database db1, db2 -Name udf1, udf2, udf3
        PS C:\> $udfs | Remove-DbaDbUdf

        Removes udf1, udf2, udf3 from db1 and db2 on the local and sql2016 SQL Server instances.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(ParameterSetName = 'NonPipeline', Mandatory = $true, Position = 0)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [PSCredential]$SqlCredential,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [string[]]$Database,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [object[]]$ExcludeDatabase,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [switch]$ExcludeSystemUdf,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [string[]]$Schema,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [string[]]$ExcludeSchema,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [string[]]$Name,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [string[]]$ExcludeName,
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.UserDefinedFunction[]]$InputObject,
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
            $udfs = Get-DbaDbUdf @params
        } else {
            $udfs += $InputObject
        }
    }

    end {
        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaDbUdf.
        foreach ($udfItem in $udfs) {
            if ($PSCmdlet.ShouldProcess($udfItem.Parent.Parent.Name, "Removing the user defined function $($udfItem.Schema).$($udfItem.Name) in the database $($udfItem.Parent.Name) on $($udfItem.Parent.Parent.Name)")) {
                $output = [PSCustomObject]@{
                    ComputerName = $udfItem.Parent.Parent.ComputerName
                    InstanceName = $udfItem.Parent.Parent.ServiceName
                    SqlInstance  = $udfItem.Parent.Parent.DomainInstanceName
                    Database     = $udfItem.Parent.Name
                    Udf          = "$($udfItem.Schema).$($udfItem.Name)"
                    UdfName      = $udfItem.Name
                    UdfSchema    = $udfItem.Schema
                    Status       = $null
                    IsRemoved    = $false
                }
                try {
                    $udfItem.Drop()
                    $output.Status = "Dropped"
                    $output.IsRemoved = $true
                } catch {
                    Stop-Function -Message "Failed removing the user defined function $($udfItem.Schema).$($udfItem.Name) in the database $($udfItem.Parent.Name) on $($udfItem.Parent.Parent.Name)" -ErrorRecord $_
                    $output.Status = (Get-ErrorMessage -Record $_)
                    $output.IsRemoved = $false
                }
                $output
            }
        }
    }
}