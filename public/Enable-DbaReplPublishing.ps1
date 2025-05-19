function Enable-DbaReplPublishing {
    <#
    .SYNOPSIS
        Enables replication publishing for the target SQL instances.

    .DESCRIPTION
        Enables replication publishing for the target SQL instances.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER SnapshotShare
        The share used to access snapshot files.

        The default is the ReplData folder within the InstallDataDirectory for the instance.

    .PARAMETER PublisherSqlLogin
        If this is used the PublisherSecurity will be set to use this.
        If not specified WindowsAuthentication will be used - this is the default, and recommended method.

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
        https://dbatools.io/Enable-DbaReplPublishing

    .EXAMPLE
        PS C:\> Enable-DbaReplPublishing -SqlInstance SqlBox1\Instance2

        Enables replication publishing for instance SqlBox1\Instance2 using Windows Auth and the default InstallDataDirectory\ReplData as the snapshot folder

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$SnapshotShare,
        [PSCredential]$PublisherSqlLogin,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {

            $replServer = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential -EnableException:$EnableException

            Write-Message -Level Verbose -Message "Enabling replication publishing for $instance"

            if ($replServer.IsDistributor) {
                try {
                    if ($PSCmdlet.ShouldProcess($instance, "Getting distribution information on $instance")) {

                        $distPublisher = New-Object Microsoft.SqlServer.Replication.DistributionPublisher
                        $distPublisher.ConnectionContext = $replServer.ConnectionContext
                        $distPublisher.Name = $instance
                        $distPublisher.DistributionDatabase = $replServer.DistributionDatabases.Name

                        if (Test-Bound SnapshotShare -Not) {
                            $SnapshotShare = Join-Path (Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential).InstallDataDirectory 'ReplData'
                            Write-Message -Level Verbose -Message ('No snapshot share specified, using default of {0}' -f $SnapshotShare)
                        }

                        $distPublisher.WorkingDirectory = $SnapshotShare
                    }

                    if ($PSCmdlet.ShouldProcess($instance, "Configuring PublisherSecurity on $instance")) {
                        if ($PublisherSqlLogin) {
                            Write-Message -Level Verbose -Message "Configuring with a SQLLogin for PublisherSecurity"
                            $distPublisher.PublisherSecurity.WindowsAuthentication = $false
                            $distPublisher.PublisherSecurity.SqlStandardLogin = $PublisherSqlLogin.UserName
                            $distPublisher.PublisherSecurity.SecureSqlStandardPassword = $PublisherSqlLogin.Password

                        } else {
                            Write-Message -Level Verbose -Message "Configuring with WindowsAuth for PublisherSecurity"
                            $distPublisher.PublisherSecurity.WindowsAuthentication = $true
                        }
                    }

                    if ($PSCmdlet.ShouldProcess($instance, "Enable publishing on $instance")) {
                        Write-Message -Level Debug -Message $distPublisher
                        # lots more properties to add as params
                        $distPublisher.Create()

                        $replServer.Refresh()
                        $replServer
                    }

                } catch {
                    Stop-Function -Message "Unable to enable replication publishing" -ErrorRecord $_ -Target $instance -Continue
                }
            } else {
                Stop-Function -Message "$instance isn't currently enabled for distributing. Please enable that first." -Target $instance -Continue
            }
        }
    }
}