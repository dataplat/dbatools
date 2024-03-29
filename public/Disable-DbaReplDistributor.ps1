function Disable-DbaReplDistributor {
    <#
    .SYNOPSIS
        Disables replication distribution for the target SQL instances.

    .DESCRIPTION
        Disables replication distribution for the target SQL instances.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Force
        Specify whether or not replication objects are removed from the server, even if a remote Distributor cannot be reached.

        If true, the publishing and Distributor configuration at the current server is uninstalled regardless of whether or not dependent publishing and distribution objects are uninstalled.

        If false, the publisher and distribution databases must already be uninstalled, and no local databases are enabled for publishing.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: repl, Replication
        Author: Jess Pomfret (@jpomfret), jesspomfret.com

        Website: https://dbatools.io
        Copyright: (c) 2023 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Disable-DbaReplDistributor

    .EXAMPLE
        PS C:\> Disable-DbaReplDistributor -SqlInstance mssql1

        Disables replication distribution for the mssql1 instance.

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Disable-DbaReplDistributor -SqlInstance mssql1, mssql2 -SqlCredential $cred -Force

        Disables replication distribution for the mssql1 and mssql2 instances using a sql login. Specifies force so the publishing and Distributor configuration at the current server is uninstalled regardless of whether or not dependent publishing and distribution objects are uninstalled.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$Force,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {

            $replServer = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential -EnableException:$EnableException

            Write-Message -Level Verbose -Message "Disabling and removing replication distribution for $instance"

            if ($replServer.IsDistributor) {
                try {
                    if ($PSCmdlet.ShouldProcess($instance, "Disabling and removing distribution on $instance")) {
                        # remove any connections to the distribution database
                        $null = Get-DbaProcess -SqlInstance $instance -SqlCredential $SqlCredential -Database $replServer.DistributionDatabases.name -EnableException:$EnableException | Stop-DbaProcess -EnableException:$EnableException
                        # uninstall distribution
                        $replServer.UninstallDistributor($Force)
                    }
                } catch {
                    Stop-Function -Message "Unable to disable replication distribution" -ErrorRecord $_ -Target $instance -Continue
                }

                $replServer.Refresh()
                $replServer

            } else {
                Stop-Function -Message "$instance isn't currently enabled for distributing." -Target $instance -Continue
            }
        }
    }
}