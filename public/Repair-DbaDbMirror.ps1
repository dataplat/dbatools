function Repair-DbaDbMirror {
    <#
    .SYNOPSIS
        Repairs suspended database mirroring sessions by restarting endpoints and resuming mirroring

    .DESCRIPTION
        Restores database mirroring functionality when mirroring sessions become suspended due to network connectivity issues, log space problems, or other transient failures. This function performs the standard troubleshooting steps that DBAs typically execute manually: stops and restarts the database mirroring endpoints on the SQL Server instance, then resumes the mirroring session between the principal and mirror databases.

        When database mirroring is suspended, the mirror database stops receiving transaction log records from the principal database, creating a potential data loss risk. This command automates the common recovery process, eliminating the need to manually restart endpoints and issue ALTER DATABASE commands to resume mirroring.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the name of the mirrored database that needs repair on the SQL Server instance.
        Use this when you know the specific database with suspended mirroring that requires endpoint restart and session resumption.
        Accepts multiple database names and supports wildcards for pattern matching.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase pipeline input to repair multiple mirrored databases in a single operation.
        Use this approach when you need to repair several databases at once or when working with the output of database filtering commands.
        Each database object must represent a database that has mirroring configured.

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