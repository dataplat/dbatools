function Remove-DbaDbPartitionFunction {
    <#
    .SYNOPSIS
        Drops partition functions from SQL Server databases to clean up unused partitioning schemes.

    .DESCRIPTION
        Removes partition functions from specified databases across one or more SQL Server instances. Partition functions define the value ranges used to split table data across multiple filegroups, and removing unused functions helps maintain a clean database schema. This command is commonly used during partition cleanup operations, schema migrations, or when decommissioning partitioned tables that no longer require their associated partition functions.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database(s) from which to remove partition functions. Accepts wildcard patterns for matching multiple databases.
        Use this to target specific databases when you need to clean up partitioning objects from particular databases rather than all databases on the instance.

    .PARAMETER ExcludeDatabase
        Excludes the specified database(s) from partition function removal operations. Auto-populated with available databases from the target server.
        Use this when you want to remove partition functions from most databases but need to preserve them in specific databases like production or critical systems.

    .PARAMETER InputObject
        Accepts partition function objects from Get-DbaDbPartitionFunction for targeted removal operations.
        Use this with pipeline operations when you need to selectively remove specific partition functions based on criteria like name patterns, usage, or dependencies.

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
        Tags: PartitionFunction, Database
        Author: Mikey Bronowski (@MikeyBronowski), bronowski.it

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbPartitionFunction

    .OUTPUTS
        PSCustomObject

        Returns one object per partition function removal attempt. The object contains information about the operation outcome regardless of success or failure.

        Properties:
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The database containing the partition function
        - PartitionFunctionName: The name of the partition function that was removed
        - Status: The outcome of the drop operation - either "Dropped" on success or the error message on failure
        - IsRemoved: Boolean indicating whether the partition function was successfully removed ($true) or not ($false)

    .EXAMPLE
        PS C:\> Remove-DbaDbPartitionFunction -SqlInstance localhost, sql2016 -Database db1, db2

        Removes partition functions from db1 and db2 on the local and sql2016 SQL Server instances.

    .EXAMPLE
        PS C:\> Get-DbaDbPartitionFunction -SqlInstance SRV1 | Out-GridView -Title 'Select partition function(s) to drop' -OutputMode Multiple | Remove-DbaDbPartitionFunction

        Using a pipeline this command gets all partition functions on SRV1, lets the user select those to remove and then removes the selected partition functions.

    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Default', ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [object[]]$ExcludeDatabase,
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.PartitionFunction[]]$InputObject,
        [Parameter(ParameterSetName = 'Pipeline')]
        [switch]$EnableException
    )

    begin {
        $partfuns = @( )
    }

    process {
        if ($SqlInstance) {
            $params = $PSBoundParameters
            $null = $params.Remove('WhatIf')
            $null = $params.Remove('Confirm')
            $partfuns = Get-DbaDbPartitionFunction @params
        } else {
            $partfuns += $InputObject
        }
    }

    end {
        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaDbPartitionFunction.
        foreach ($partfunItem in $partfuns) {
            if ($PSCmdlet.ShouldProcess($partfunItem.Parent.Parent.Name, "Removing the partition function [$($partfunItem.Name)] in the database [$($partfunItem.Parent.Name)] on [$($partfunItem.Parent.Parent.Name)]")) {
                $output = [PSCustomObject]@{
                    ComputerName          = $partfunItem.Parent.Parent.ComputerName
                    InstanceName          = $partfunItem.Parent.Parent.ServiceName
                    SqlInstance           = $partfunItem.Parent.Parent.DomainInstanceName
                    Database              = $partfunItem.Parent.Name
                    PartitionFunctionName = $partfunItem.Name
                    Status                = $null
                    IsRemoved             = $false
                }
                try {
                    $partfunItem.Drop()
                    $output.Status = "Dropped"
                    $output.IsRemoved = $true
                } catch {
                    Stop-Function -Message "Failed removing the partition function [$($partfunItem.Name)] in the database [$($partfunItem.Parent.Name)] on [$($partfunItem.Parent.Parent.Name)]" -ErrorRecord $_
                    $output.Status = (Get-ErrorMessage -Record $_)
                    $output.IsRemoved = $false
                }
                $output
            }
        }
    }
}