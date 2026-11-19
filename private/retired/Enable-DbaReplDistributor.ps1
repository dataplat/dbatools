function Enable-DbaReplDistributor {
    <#
    .SYNOPSIS
        Configures a SQL Server instance as a replication distributor with distribution database

    .DESCRIPTION
        Configures the specified SQL Server instance to act as a replication distributor by creating the distribution database and installing the distributor role. This is the first step in setting up SQL Server replication, as the distributor manages the flow of replicated transactions between publishers and subscribers. Once configured, the instance can store replication metadata, track publication and subscription information, and coordinate data movement for transactional and snapshot replication scenarios.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER DistributionDatabase
        Specifies the name of the distribution database that will be created to store replication metadata and transaction logs.
        This database holds subscription information, publication details, and queued transactions for distribution to subscribers.
        Defaults to 'distribution' if not specified, which is the standard convention for most replication configurations.

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

        Returns one ReplicationServer object per instance configured as a distributor. The object shows the distributor configuration and replication server role details after enabling distribution.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - IsDistributor: Boolean indicating whether the instance is configured as a distributor
        - IsPublisher: Boolean indicating whether the instance is configured as a publisher
        - DistributionServer: Name of the distribution server
        - DistributionDatabase: Name of the distribution database that stores replication metadata

        Additional properties available (from SMO ReplicationServer object):
        - DistributionDatabases: Collection of distribution databases configured on the distributor
        - DistributorSecurity: Distribution agent credentials and security settings
        - LocalPublisher: Boolean indicating if this server can function as a local publisher
        - PublisherIdentity: Identity of the publisher
        - ReplicationDatabases: Collection of databases enabled for replication on this instance
        - SubscriptionServers: List of subscription servers
        - ThirdPartySubscribers: Information about non-SQL Server subscribers

        All properties from the base SMO ReplicationServer object are accessible even though only default properties are displayed without using Select-Object *.

    .NOTES
        Tags: repl, Replication
        Author: Jess Pomfret (@jpomfret), jesspomfret.com

        Website: https://dbatools.io
        Copyright: (c) 2023 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Enable-DbaReplDistributor

    .EXAMPLE
        PS C:\> Enable-DbaReplDistributor -SqlInstance mssql1

        Enables distribution for the mssql1 instance.

    .EXAMPLE
        PS C:\> Enable-DbaReplDistributor -SqlInstance mssql1 -DistributionDatabase repDatabase

        Enables distribution for the mssql1 instance and names the distribution database repDatabase.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$DistributionDatabase = 'distribution',
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {

            $replServer = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential -EnableException:$EnableException

            Write-Message -Level Verbose -Message "Enabling replication distribution for $instance"

            try {
                if ($PSCmdlet.ShouldProcess($instance, "Enabling distributor for $instance")) {
                    $distributionDb = New-Object Microsoft.SqlServer.Replication.DistributionDatabase
                    $distributionDb.ConnectionContext = $replServer.ConnectionContext
                    $distributionDb.Name = $DistributionDatabase

                    #TODO: lots more properties to add as params
                    $replServer.InstallDistributor($null, $distributionDb)

                    $replServer.Refresh()
                    $replServer
                }
            } catch {
                Stop-Function -Message "Unable to enable replication distributor" -ErrorRecord $_ -Target $instance -Continue
            }
        }
    }
}