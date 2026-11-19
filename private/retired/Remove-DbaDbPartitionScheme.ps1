function Remove-DbaDbPartitionScheme {
    <#
    .SYNOPSIS
        Removes database partition schemes from SQL Server databases.

    .DESCRIPTION
        Removes partition schemes from specified databases across one or more SQL Server instances. Partition schemes define how partitioned tables and indexes map to filegroups, and this function helps clean up unused schemes during database reorganization or migration projects.

        The function integrates seamlessly with Get-DbaDbPartitionScheme through pipeline support, allowing you to first identify partition schemes and then selectively remove them. This is particularly useful when consolidating databases or simplifying partition strategies.

        Each removal operation includes confirmation prompts by default to prevent accidental deletion of partition schemes that may still be referenced by tables or indexes.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to scan for partition schemes to remove. Accepts multiple database names.
        Use this when you need to remove partition schemes from specific databases rather than all databases on the instance, such as during database decommissioning or partition strategy simplification.

    .PARAMETER ExcludeDatabase
        Specifies databases to skip when scanning for partition schemes to remove. Accepts multiple database names.
        Use this to exclude system databases or specific databases you want to preserve during bulk partition scheme cleanup operations.

    .PARAMETER InputObject
        Accepts partition scheme objects piped from Get-DbaDbPartitionScheme for targeted removal operations.
        Use this for selective removal workflows where you first identify specific partition schemes and then remove only those schemes.

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
        Tags: PartitionScheme, Partition, Database
        Author: Mikey Bronowski (@MikeyBronowski), bronowski.it

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        PSCustomObject

        Returns one object per partition scheme removal operation with the following properties:

        - ComputerName: The name of the computer where the SQL Server instance is running
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The name of the database containing the partition scheme
        - PartitionSchemeName: The name of the partition scheme that was processed
        - Status: The result of the removal operation ("Dropped" on success, or error message on failure)
        - IsRemoved: Boolean indicating whether the partition scheme was successfully dropped (true) or failed (false)

    .LINK
        https://dbatools.io/Remove-DbaDbPartitionScheme

    .EXAMPLE
        PS C:\> Remove-DbaDbPartitionScheme -SqlInstance localhost, sql2016 -Database db1, db2

        Removes partition schemes from db1 and db2 on the local and sql2016 SQL Server instances.

    .EXAMPLE
        PS C:\> Get-DbaDbPartitionScheme -SqlInstance SRV1 | Out-GridView -Title 'Select partition scheme(s) to drop' -OutputMode Multiple | Remove-DbaDbPartitionScheme

        Using a pipeline this command gets all partition schemes on SRV1, lets the user select those to remove and then removes the selected partition schemes.

    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Default', ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [object[]]$ExcludeDatabase,
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.PartitionScheme[]]$InputObject,
        [Parameter(ParameterSetName = 'Pipeline')]
        [switch]$EnableException
    )

    begin {
        $partschs = @( )
    }

    process {
        if ($SqlInstance) {
            $params = $PSBoundParameters
            $null = $params.Remove('WhatIf')
            $null = $params.Remove('Confirm')
            $partschs = Get-DbaDbPartitionScheme @params
        } else {
            $partschs += $InputObject
        }
    }

    end {
        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaDbPartitionScheme.
        foreach ($partschItem in $partschs) {
            if ($PSCmdlet.ShouldProcess($partschItem.Parent.Parent.Name, "Removing the partition scheme [$($partschItem.Name)] in the database [$($partschItem.Parent.Name)] on [$($partschItem.Parent.Parent.Name)]")) {
                $output = [PSCustomObject]@{
                    ComputerName        = $partschItem.Parent.Parent.ComputerName
                    InstanceName        = $partschItem.Parent.Parent.ServiceName
                    SqlInstance         = $partschItem.Parent.Parent.DomainInstanceName
                    Database            = $partschItem.Parent.Name
                    PartitionSchemeName = $partschItem.Name
                    Status              = $null
                    IsRemoved           = $false
                }
                try {
                    $partschItem.Drop()
                    $output.Status = "Dropped"
                    $output.IsRemoved = $true
                } catch {
                    Stop-Function -Message "Failed removing the partition scheme $($partschItem.Name) in the database [$($partschItem.Parent.Name)] on [$($partschItem.Parent.Parent.Name)]" -ErrorRecord $_
                    $output.Status = (Get-ErrorMessage -Record $_)
                    $output.IsRemoved = $false
                }
                $output
            }
        }
    }
}