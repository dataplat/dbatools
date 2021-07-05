function Remove-DbaDbView {
    <#
    .SYNOPSIS
        Removes a database view from database(s) for each instance(s) of SQL Server.

    .DESCRIPTION
        The Remove-DbaDbView removes view(s) from database(s) for each instance(s) of SQL Server.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Enables piped input from Get-DbaDbView

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: View, Database
        Author: Mikey Bronowski (@MikeyBronowski), https://bronowski.it

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbView

    .EXAMPLE
        PS C:\> $views = Get-DbaDbView -SqlInstance localhost, sql2016 -Database db1, db2 -View view1, view2, view3
        PS C:\> $views | Remove-DbaDbView

        Removes view1, view2, view3 from db1 and db2 on the local and sql2016 SQL Server instances.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.View[]]$InputObject,
        [switch]$EnableException
    )

    process {

        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a view, database, or server or specify a SqlInstance"
            return
        }

        foreach ($vw in $InputObject) {

            if ($Pscmdlet.ShouldProcess($vw.SqlInstance, "Removing the view $vw in the database $($vw.Parent.Name)")) {
                try {
                    $vw.Drop()
                } catch {
                    Stop-Function -Message "Failure on $($vw.SqlInstance) to drop the view $vw in the database $($vw.Parent.Name)" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}