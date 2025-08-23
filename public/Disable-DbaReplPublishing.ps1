function Disable-DbaReplPublishing {
    <#
    .SYNOPSIS
        Disables replication publishing on SQL Server instances and removes publisher configuration.

    .DESCRIPTION
        Removes the publisher role from SQL Server instances that are currently configured for replication publishing. This function safely dismantles the publishing configuration by removing the publisher from the distributor, which stops all publication activity on the target instance. Use this when decommissioning replication setups or troubleshooting publisher configuration issues that require a clean restart.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Force
        Forces the removal of publisher configuration without verifying the distributor connection status.
        Use this when the distributor server is unreachable or when you need to forcibly clean up orphaned replication objects.
        Without this switch, the function will fail if it cannot communicate with the distributor to perform proper cleanup verification.

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
        https://dbatools.io/Disable-DbaReplPublishing

    .EXAMPLE
        PS C:\> Disable-DbaReplPublishing -SqlInstance mssql1

        Disables replication distribution for the mssql1 instance.

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Disable-DbaReplPublishing -SqlInstance mssql1, mssql2 -SqlCredential $cred -Force

        Disables replication distribution for the mssql1 and mssql2 instances using a sql login.

        Specifies force so all the replication objects associated with the Publisher are dropped even
        if the Publisher is on a remote server that cannot be reached.
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

            Write-Message -Level Verbose -Message "Disabling and removing publishing for $instance"

            if ($replServer.IsPublisher) {
                try {
                    if ($PSCmdlet.ShouldProcess($instance, "Disabling and removing publishing on $instance")) {
                        $replServer.DistributionPublishers.Remove($Force)
                    }

                    $replServer.Refresh()
                    $replServer

                } catch {
                    Stop-Function -Message "Unable to disable replication publishing" -ErrorRecord $_ -Target $instance -Continue
                }
            } else {
                Stop-Function -Message "$instance isn't currently enabled for publishing." -Continue -ContinueLabel main -Target $instance -Category ObjectNotFound
            }
        }
    }
}