function Remove-DbaDbView {
    <#
    .SYNOPSIS
        Removes database views from SQL Server databases

    .DESCRIPTION
        Removes one or more database views from specified databases and SQL Server instances. This function streamlines the cleanup of obsolete views during database refactoring, development cleanup, or schema maintenance tasks. You can specify views individually by name or use pipeline input from Get-DbaDbView for bulk operations. Each removal operation includes detailed status reporting and supports WhatIf testing to preview changes before execution.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to search for views to remove. Accepts multiple database names.
        Use this to limit view removal to specific databases instead of searching all databases on the instance.

    .PARAMETER View
        Specifies the names of the views to remove. Accepts multiple view names and supports wildcards for pattern matching.
        When targeting views in specific schemas, use the two-part naming convention like 'dbo.ViewName'.

    .PARAMETER InputObject
        Accepts view objects from Get-DbaDbView for pipeline operations. Use this for complex filtering scenarios or bulk removals.
        This approach provides better control over which specific views get removed compared to using name-based targeting.

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
        Tags: View, Database
        Author: Mikey Bronowski (@MikeyBronowski), bronowski.it

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbView

    .OUTPUTS
        PSCustomObject

        Returns one object per view removed, with the following properties:
        - ComputerName: The computer name of the SQL Server instance where the view was removed
        - InstanceName: The SQL Server instance name where the view was removed
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The database name from which the view was removed
        - View: The schema-qualified view name in the format 'schema.viewname' (e.g., 'dbo.MyView')
        - ViewName: The view name only (without schema prefix)
        - ViewSchema: The schema name containing the view
        - Status: Result of the removal operation - "Dropped" on success or the error message on failure
        - IsRemoved: Boolean indicating whether the view was successfully removed ($true) or failed ($false)

    .EXAMPLE
        PS C:\> Remove-DbaDbView -SqlInstance localhost, sql2016 -Database db1, db2 -View view1, view2, view3

        Removes view1, view2, view3 from db1 and db2 on the local and sql2016 SQL Server instances.

    .EXAMPLE
        PS C:\> $views = Get-DbaDbView -SqlInstance localhost, sql2016 -Database db1, db2 -View view1, view2, view3
        PS C:\> $views | Remove-DbaDbView

        Removes view1, view2, view3 from db1 and db2 on the local and sql2016 SQL Server instances.
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
        [string[]]$View,
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.View[]]$InputObject,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [switch]$EnableException
    )

    begin {
        $views = @( )
    }

    process {
        if ($SqlInstance) {
            $params = $PSBoundParameters
            $null = $params.Remove('WhatIf')
            $null = $params.Remove('Confirm')
            $views = Get-DbaDbView @params
        } else {
            $views += $InputObject
        }
    }

    end {
        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaDbView.
        foreach ($viewItem in $views) {
            if ($PSCmdlet.ShouldProcess($viewItem.Parent.Parent.Name, "Removing the view $($viewItem.Schema).$($viewItem.Name) in the database $($viewItem.Parent.Name) on $($viewItem.Parent.Parent.Name)")) {
                $output = [PSCustomObject]@{
                    ComputerName = $viewItem.Parent.Parent.ComputerName
                    InstanceName = $viewItem.Parent.Parent.ServiceName
                    SqlInstance  = $viewItem.Parent.Parent.DomainInstanceName
                    Database     = $viewItem.Parent.Name
                    View         = "$($viewItem.Schema).$($viewItem.Name)"
                    ViewName     = $viewItem.Name
                    ViewSchema   = $viewItem.Schema
                    Status       = $null
                    IsRemoved    = $false
                }
                try {
                    $viewItem.Drop()
                    $output.Status = "Dropped"
                    $output.IsRemoved = $true
                } catch {
                    Stop-Function -Message "Failed removing the view $($viewItem.Schema).$($viewItem.Name) in the database $($viewItem.Parent.Name) on $($viewItem.Parent.Parent.Name)" -ErrorRecord $_
                    $output.Status = (Get-ErrorMessage -Record $_)
                    $output.IsRemoved = $false
                }
                $output
            }
        }
    }
}