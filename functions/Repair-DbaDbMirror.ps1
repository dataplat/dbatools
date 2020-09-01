function Repair-DbaDbMirror {
    <#
    .SYNOPSIS
        Attempts to repair a suspended or paused mirroring database.

    .DESCRIPTION
        Attempts to repair a suspended mirroring database.

        Restarts the endpoints then sets the partner to resume. See this article for more info:

        http://www.sqlservercentral.com/blogs/vivekssqlnotes/2016/09/03/how-to-resume-suspended-database-mirroring-in-sql-server-/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The target database.

    .PARAMETER InputObject
        Allows piping from Get-DbaDatabase.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Mirroring, Mirror, HA
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Repair-DbaDbMirror

    .EXAMPLE
        PS C:\> Repair-DbaDbMirror -SqlInstance sql2017 -Database pubs

        Attempts to repair the mirrored but suspended pubs database on sql2017.
        Restarts the endpoints then sets the partner to resume. Prompts for confirmation.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2017 -Database pubs | Repair-DbaDbMirror -Confirm:$false

        Attempts to repair the mirrored but suspended pubs database on sql2017.
        Restarts the endpoints then sets the partner to resume. Does not prompt for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when SqlInstance is specified"
            return
        }
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            try {
                Get-DbaEndpoint -SqlInstance $db.Parent | Where-Object EndpointType -eq DatabaseMirroring | Stop-DbaEndpoint
                Get-DbaEndpoint -SqlInstance $db.Parent | Where-Object EndpointType -eq DatabaseMirroring | Start-DbaEndpoint
                $db | Set-DbaDbMirror -State Resume
                if ($Pscmdlet.ShouldProcess("console", "displaying output")) {
                    $db
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_
            }
        }
    }
}