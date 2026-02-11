function Enable-DbaReplPublishing {
    <#
    .SYNOPSIS
        Configures a SQL Server instance as a replication publisher on an existing distributor.

    .DESCRIPTION
        Configures a SQL Server instance to publish data for replication by creating the necessary publisher configuration on an existing distributor. This is typically the second step in setting up SQL Server replication, after the distributor has been configured with Enable-DbaReplDistributor. The function sets up the snapshot working directory, configures publisher security authentication, and registers the instance as a publisher with the distribution database. The target instance must already be configured as a distributor before running this command.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER SnapshotShare
        Specifies the network share path where replication snapshot files will be stored and accessed by subscribers.
        Use this when you need snapshot files in a specific location for network access or storage requirements.
        Defaults to InstallDataDirectory\ReplData if not specified.

    .PARAMETER PublisherSqlLogin
        SQL Server login credentials to use for publisher security authentication instead of Windows Authentication.
        Use this when the distributor and publisher are in different domains or when Windows Authentication is not available.
        Windows Authentication is used by default and is the recommended method for security.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .OUTPUTS
        Microsoft.SqlServer.Replication.ReplicationServer

        Returns one ReplicationServer object per instance specified, representing the publisher configuration. The object is refreshed after the publishing configuration is created, reflecting the updated replication state.

        Default display properties (inherited from Get-DbaReplServer via Select-DefaultView):
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - IsDistributor: Boolean indicating whether this instance is configured as a distributor
        - IsPublisher: Boolean indicating whether this instance is configured as a publisher (should be True after this command completes)
        - DistributionServer: The name of the server configured as the distributor
        - DistributionDatabase: The name of the distribution database

        Additional properties available (from SMO ReplicationServer object):
        - DistributionDatabases: Collection of distribution databases configured on the instance
        - DistributionPublishers: Collection of publishers configured on the distributor
        - RegisteredSubscribers: Collection of registered subscribers
        - ReplicationDatabases: Collection of databases enabled for replication

        All properties from the base SMO ReplicationServer object are accessible using Select-Object *.

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