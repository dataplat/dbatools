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
        The target database(s).

    .PARAMETER View
        The name(s) of the view(s).

    .PARAMETER InputObject
        Allows piping from Get-DbaDbView.

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