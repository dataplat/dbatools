function Get-DbaReplSubscription {
    <#
    .SYNOPSIS
        Retrieves SQL Server replication subscription details for publications across instances.

    .DESCRIPTION
        Retrieves detailed information about replication subscriptions, showing which subscriber instances are receiving data from publications. This is essential for monitoring replication topology, troubleshooting subscription issues, and auditing data distribution across your SQL Server environment. You can filter results by database, publication name, subscriber instance, subscription database, or subscription type (Push/Pull) to focus on specific replication relationships.

        Pull subscriptions that exist only in the distribution database (but not in the publisher's syssubscriptions) are also returned, to handle cases where subscriptions were set up outside the normal creation process.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which publication databases to include when retrieving subscriptions. Accepts multiple database names and wildcards.
        Use this to focus on subscriptions from specific databases instead of checking all replicated databases on the instance.

    .PARAMETER PublicationName
        Filters results to subscriptions from specific publications by name. Accepts multiple publication names.
        Use this when you need to check subscription status for particular publications rather than all publications on the server.

    .PARAMETER SubscriberName
        Filters results to subscriptions where data is being delivered to specific subscriber instances. Accepts multiple instance names.
        Use this to monitor subscription health and activity for particular subscriber servers in your replication topology.

    .PARAMETER SubscriptionDatabase
        Filters results to subscriptions where data is being delivered to specific databases on subscriber instances. Accepts multiple database names.
        Use this to track how data flows to particular databases across your subscribers, especially when subscription databases have different names than source databases.

    .PARAMETER Type
        Filters results to subscriptions of a specific delivery method (Push or Pull). Push subscriptions are managed by the publisher, while Pull subscriptions are managed by the subscriber.
        Use this to separate subscription management tasks or troubleshoot issues specific to push or pull delivery mechanisms.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: repl, Replication
        Author: Jess Pomfret (@jpomfret), jesspomfret.com

        Website: https://dbatools.io
        Copyright: (c) 2023 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        Microsoft.SqlServer.Replication.Subscription

        Returns one Subscription object per subscription found across all qualifying publications. Each object represents a replication relationship between a publisher and subscriber, showing subscription details, delivery method, and synchronization information.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance (publisher)
        - InstanceName: The SQL Server instance name (publisher)
        - SqlInstance: The full SQL Server instance name (computer\instance) for the publisher
        - DatabaseName: The name of the publication database on the publisher
        - PublicationName: The name of the publication being subscribed to
        - Name: The name of the subscription
        - SubscriberName: The name of the Subscriber instance receiving replicated data
        - SubscriptionDBName: The name of the database on the Subscriber receiving the data
        - SubscriptionType: The type of subscription delivery (Push or Pull)

        Additional properties available (from SMO Subscription object):
        - AgentJobId: The unique identifier of the agent job used for subscription synchronization
        - AgentSchedule: The schedule for the synchronization agent job execution
        - SynchronizationAgentName: The name of the synchronization agent job
        - Status: The current status of the subscription (Active, Inactive, Uninitialized, etc.)
        - SyncType: The manner in which the subscription is initialized (Automatic, None, Replicating)
        - SubscriberSecurity: The security context for Subscriber connections
        - SynchronizationAgentProcessSecurity: The Windows account credentials for the agent process

        All properties from the base SMO Subscription object are accessible using Select-Object *.

    .LINK
        https://dbatools.io/Get-DbaReplSubscription

    .EXAMPLE
        PS C:\> Get-DbaReplSubscription -SqlInstance mssql1

        Return all subscriptions for all publications on server mssql1.

    .EXAMPLE
        PS C:\> Get-DbaReplSubscription -SqlInstance mssql1 -Database TestDB

        Return all subscriptions for all publications on server mssql1 for only the TestDB database.

    .EXAMPLE
        PS C:\> Get-DbaReplSubscription -SqlInstance mssql1 -PublicationName Mergey

        Return all subscriptions for the publication Mergey on server mssql1.

    .EXAMPLE
        PS C:\> Get-DbaReplSubscription -SqlInstance mssql1 -Type Push

        Return all subscriptions for all transactional publications on server mssql1.

    .EXAMPLE
        PS C:\> Get-DbaReplSubscription -SqlInstance mssql1 -SubscriberName mssql2

        Return all subscriptions for all publications on server mssql1 where the subscriber is mssql2.

    .EXAMPLE
        PS C:\> Get-DbaReplSubscription -SqlInstance mssql1 -SubscriptionDatabase TestDB

        Return all subscriptions for all publications on server mssql1 where the subscription database is TestDB.

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Object[]]$Database,
        [String[]]$PublicationName,
        [DbaInstanceParameter[]]$SubscriberName,
        [Object[]]$SubscriptionDatabase,
        [Alias("PublicationType")]
        [ValidateSet("Push", "Pull")]
        [Object[]]$Type,
        [Switch]$EnableException
    )
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $publications = Get-DbaReplPublication -SqlInstance $server -EnableException:$EnableException

                if ($Database) {
                    $publications = $publications | Where-Object DatabaseName -in $Database
                }

                if ($PublicationName) {
                    $publications = $publications | Where-Object Name -in $PublicationName
                }

            } catch {
                Stop-Function -Message "Error occurred while getting publications from $instance" -ErrorRecord $_ -Target $instance -Continue
            }

            # Track subscriptions already emitted to avoid duplicates from the distribution DB check
            $foundSubscriptionKeys = @{}

            try {
                foreach ($subs in $publications.Subscriptions) {
                    Write-Message -Level Verbose -Message ('Get subscriptions for {0}' -f $sub.PublicationName)

                    if ($SubscriberName) {
                        $subs = $subs | Where-Object SubscriberName -eq $SubscriberName
                    }

                    if ($SubscriptionDatabase) {
                        $subs = $subs | Where-Object SubscriptionDBName -eq $SubscriptionDatabase
                    }

                    if ($Type) {
                        $subs = $subs | Where-Object SubscriptionType -eq $Type
                    }

                    foreach ($sub in $subs) {
                        $subKey = "$($sub.SubscriberName)|$($sub.SubscriptionDBName)|$($sub.PublicationName)|$($sub.DatabaseName)"
                        $foundSubscriptionKeys[$subKey] = $true

                        Add-Member -Force -InputObject $sub -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                        Add-Member -Force -InputObject $sub -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                        Add-Member -Force -InputObject $sub -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName

                        Select-DefaultView -InputObject $sub -Property ComputerName, InstanceName, SqlInstance, DatabaseName, PublicationName, Name, SubscriberName, SubscriptionDBName, SubscriptionType
                    }
                }
            } catch {
                Stop-Function -Message "Error occurred while getting subscriptions from $instance" -ErrorRecord $_ -Target $instance -Continue
            }

            # Also check distribution database for pull subscriptions that may be missing from publisher's syssubscriptions.
            # This handles cases where pull subscriptions were created outside the normal process and only exist in distribution.dbo.MSsubscriptions.
            if (-not $Type -or "Pull" -in $Type) {
                try {
                    $replServer = New-Object Microsoft.SqlServer.Replication.ReplicationServer
                    $replServer.ConnectionContext = $server.ConnectionContext

                    if ($replServer.IsPublisher -and $replServer.DistributorInstalled -and $replServer.DistributorAvailable) {
                        $distributorName = $replServer.DistributionServer
                        $distributionDbName = $replServer.DistributionDatabase

                        try {
                            # Reuse the existing connection if the distributor is the same server
                            if ($distributorName -eq $server.ComputerName -or $distributorName -eq $server.DomainInstanceName) {
                                $distributorServer = $server
                            } else {
                                $distributorServer = Connect-DbaInstance -SqlInstance $distributorName -SqlCredential $SqlCredential
                            }

                            $distQuery = "
                                SELECT DISTINCT
                                    a.subscriber_name AS SubscriberName,
                                    a.subscriber_db   AS SubscriptionDBName,
                                    p.publisher_db    AS DatabaseName,
                                    p.publication     AS PublicationName
                                FROM MSdistribution_agents a
                                INNER JOIN MSsubscriptions s ON s.agent_id = a.id AND s.subscription_type = 1
                                INNER JOIN MSpublications p ON p.publication_id = s.publication_id
                            "

                            $splatDistQuery = @{
                                SqlInstance = $distributorServer
                                Database    = $distributionDbName
                                Query       = $distQuery
                            }
                            $distPullSubs = Invoke-DbaQuery @splatDistQuery

                            # Build a lookup of the publications we queried so we only include relevant subscriptions
                            $publicationKeys = @{}
                            foreach ($pub in $publications) {
                                $pubKey = "$($pub.DatabaseName)|$($pub.Name)"
                                $publicationKeys[$pubKey] = $true
                            }

                            # Convert SubscriberName filter to strings for comparison
                            $subscriberNameStrings = @()
                            if ($SubscriberName) {
                                $subscriberNameStrings = $SubscriberName | ForEach-Object { $_.ToString() }
                            }

                            foreach ($distSub in $distPullSubs) {
                                # Only process subscriptions for publications we already queried
                                $pubKey = "$($distSub.DatabaseName)|$($distSub.PublicationName)"
                                if (-not $publicationKeys.ContainsKey($pubKey)) { continue }

                                # Apply subscriber name filter
                                if ($subscriberNameStrings -and $distSub.SubscriberName -notin $subscriberNameStrings) { continue }

                                # Apply subscription database filter
                                if ($SubscriptionDatabase -and $distSub.SubscriptionDBName -notin $SubscriptionDatabase) { continue }

                                # Skip subscriptions already returned via SMO
                                $subKey = "$($distSub.SubscriberName)|$($distSub.SubscriptionDBName)|$($distSub.PublicationName)|$($distSub.DatabaseName)"
                                if ($foundSubscriptionKeys.ContainsKey($subKey)) { continue }

                                # Emit subscriptions found only in the distribution database
                                $subObj = [PSCustomObject]@{
                                    ComputerName       = $server.ComputerName
                                    InstanceName       = $server.ServiceName
                                    SqlInstance        = $server.DomainInstanceName
                                    DatabaseName       = $distSub.DatabaseName
                                    PublicationName    = $distSub.PublicationName
                                    Name               = "$($distSub.PublicationName)-$($distSub.SubscriberName)-$($distSub.SubscriptionDBName)"
                                    SubscriberName     = $distSub.SubscriberName
                                    SubscriptionDBName = $distSub.SubscriptionDBName
                                    SubscriptionType   = "Pull"
                                }

                                Select-DefaultView -InputObject $subObj -Property ComputerName, InstanceName, SqlInstance, DatabaseName, PublicationName, Name, SubscriberName, SubscriptionDBName, SubscriptionType
                            }
                        } catch {
                            Write-Message -Level Warning -Message "Could not query distribution database on $distributorName for additional pull subscriptions from $instance"
                        }
                    }
                } catch {
                    Write-Message -Level Verbose -Message "Unable to check distribution database for additional pull subscriptions from $instance"
                }
            }
        }
    }
}
