function Add-DbaDbMirrorMonitor {
    <#
    .SYNOPSIS
        Creates a database mirroring monitor job that periodically updates the mirroring status for every mirrored database on the server instance.

    .DESCRIPTION
        Creates a database mirroring monitor job that periodically updates the mirroring status for every mirrored database on the server instance.

        Basically executes sp_dbmmonitoraddmonitoring.

    .PARAMETER SqlInstance
        The target SQL Server instance

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

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
        https://dbatools.io/Add-DbaDbMirrorMonitor

    .EXAMPLE
        PS C:\> Add-DbaDbMirrorMonitor -SqlInstance sql2008, sql2012

        Creates a database mirroring monitor job that periodically updates the mirroring status for every mirrored database on sql2008 and sql2012.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Pscmdlet.ShouldProcess($instance, "add mirror monitoring")) {
                try {
                    $server.Query("msdb.dbo.sp_dbmmonitoraddmonitoring")
                    [pscustomobject]@{
                        ComputerName  = $server.ComputerName
                        InstanceName  = $server.ServiceName
                        SqlInstance   = $server.DomainInstanceName
                        MonitorStatus = "Added"
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}