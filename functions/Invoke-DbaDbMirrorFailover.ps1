function Invoke-DbaDbMirrorFailover {
    <#
    .SYNOPSIS
        Failover a mirrored database

    .DESCRIPTION
        Failover a mirrored database

    .PARAMETER SqlInstance
        SQL Server name or SMO object representing the primary SQL Server.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database or databases to mirror

    .PARAMETER InputObject
        Allows piping from Get-DbaDatabase

    .PARAMETER Force
        Force Failover and allow data loss

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

        TODO: add service accounts

    .LINK
        https://dbatools.io/Invoke-DbaDbMirrorFailover

    .EXAMPLE
        PS C:\> Invoke-DbaDbMirrorFailover -SqlInstance sql2016 -Database pubs

        Fails over the pubs database on sql2016. Prompts for confirmation.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016 -Database pubs | Invoke-DbaDbMirrorFailover -Force -Confirm:$false

        Forces the failover of the pubs database on sql2016 and allows data loss.
        Does not prompt for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when SqlInstance is specified"
            return
        }

        $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database

        foreach ($db in $InputObject) {
            # if it's async, you have to break the mirroring and allow data loss
            # alter database set partner force_service_allow_data_loss
            # if it's sync mirroring you know it's all in sync, so you can just do alter database [dbname] set partner failover
            if ($Force) {
                if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Forcing failover of $db and allowing data loss")) {
                    $db | Set-DbaDbMirror -State ForceFailoverAndAllowDataLoss
                }
            } else {
                if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Setting safety level to full and failing over $db to partner server")) {
                    $db | Set-DbaDbMirror -SafetyLevel Full
                    $db | Set-DbaDbMirror -State Failover
                }
            }
        }
    }
}