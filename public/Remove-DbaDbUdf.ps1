function Remove-DbaDbUdf {
    <#
    .SYNOPSIS
        Removes user-defined functions and user-defined aggregates from SQL Server databases.

    .DESCRIPTION
        Removes user-defined functions and user-defined aggregates from specified databases, providing a clean way to drop obsolete or unwanted UDFs and UDAs without manual T-SQL scripting. This function is particularly useful during database cleanup operations, code refactoring projects, or when removing deprecated functions that are no longer needed. Supports filtering by schema and function name, and can exclude system UDFs to prevent accidental removal of built-in functions. Works seamlessly with Get-DbaDbUdf for pipeline operations.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to process for UDF removal. Accepts multiple database names and supports wildcards.
        Use this to limit the operation to specific databases instead of processing all databases on the instance.

    .PARAMETER ExcludeDatabase
        Specifies databases to skip during UDF removal operations. Auto-populated with server database names for tab completion.
        Use this when you want to process most databases but exclude specific ones like production or system databases.

    .PARAMETER ExcludeSystemUdf
        Excludes system-generated and built-in user-defined functions from removal operations.
        Use this safety switch to prevent accidental deletion of system UDFs that may be required for database functionality.

    .PARAMETER Schema
        Specifies which schemas to include when removing UDFs. Accepts multiple schema names.
        Use this to target UDFs in specific schemas like 'dbo', 'reporting', or custom application schemas while leaving others untouched.

    .PARAMETER ExcludeSchema
        Specifies schemas to skip during UDF removal operations.
        Use this to protect critical schemas from modification while processing UDFs in other schemas throughout the database.

    .PARAMETER Name
        Specifies the exact names of UDFs to remove. Accepts multiple function names and supports wildcards.
        Use this for targeted removal of specific functions like deprecated calculation functions or obsolete business logic UDFs.

    .PARAMETER ExcludeName
        Specifies UDF names to skip during removal operations. Accepts multiple function names and wildcards.
        Use this to protect specific functions from deletion while removing others that match your criteria.

    .PARAMETER InputObject
        Accepts UDF and UDA objects directly from Get-DbaDbUdf pipeline operations.
        Use this when you need to filter or examine UDFs or UDAs first before removal, enabling complex selection logic not possible with simple name matching.

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
        [object[]]$InputObject,
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