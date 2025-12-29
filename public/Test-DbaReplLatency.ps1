function Test-DbaReplLatency {
    <#
    .SYNOPSIS
        Measures transactional replication latency using tracer tokens across publisher, distributor, and subscriber instances.

    .DESCRIPTION
        Creates tracer tokens in transactional replication publications and measures the time it takes for those tokens to travel from the publisher to the distributor, and from the distributor to each subscriber. This provides real-time latency measurements that help DBAs identify replication performance bottlenecks and validate that data changes are flowing through the replication topology within acceptable timeframes.

        The function connects to both the publisher and distributor instances to inject tracer tokens and retrieve timing information. You can monitor latency for all publications on an instance, specific databases, or individual publications. The latency measurements include publisher-to-distributor time, distributor-to-subscriber time, and total end-to-end latency for each subscriber.

        This is particularly useful when troubleshooting slow replication, validating replication performance after configuration changes, or establishing baseline performance metrics for replication monitoring.

        All replication commands need SQL Server Management Studio installed and are therefore currently not supported.
        Have a look at this issue to get more information: https://github.com/dataplat/dbatools/issues/7428

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Database
        Specifies which databases containing transactional replication publications to test for latency. Accepts wildcards for pattern matching.
        Use this when you need to focus on specific publication databases instead of testing all replicated databases on the instance.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER PublicationName
        Specifies which transactional replication publications to test for latency. Accepts wildcards for pattern matching.
        Use this when you need to test specific publications instead of all transactional publications in the specified databases.

    .PARAMETER TimeToLive
        Sets the maximum time in seconds to wait for tracer tokens to travel from publisher through distributor to all subscribers.
        Use this to prevent the function from hanging indefinitely when replication is severely delayed or broken. If the timeout is reached, the function reports incomplete latency data and continues to the next publication.

    .PARAMETER RetainToken
        Keeps the tracer tokens in the distribution database after latency testing is complete instead of automatically cleaning them up.
        Use this when you need to preserve tracer token history for further analysis or troubleshooting. Without this switch, tokens are automatically removed to prevent distribution database bloat.

    .PARAMETER DisplayTokenHistory
        Shows latency measurements for all existing tracer tokens in each publication instead of just the newly created token.
        Use this to see historical latency patterns and trends for ongoing replication monitoring. Without this switch, only the current test token results are displayed.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Replication
        Author: Colin Douglas

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaReplLatency

    .OUTPUTS
        PSCustomObject

        Returns one object per tracer token result per subscriber in each transactional replication publication. When using -DisplayTokenHistory, multiple objects per token are returned for historical token data. Each object represents the latency measurements for one tracer token's journey from publisher to a specific subscriber database.

        Properties:
        - ComputerName (string): The name of the computer hosting the publisher SQL Server instance
        - InstanceName (string): The SQL Server instance name of the publisher
        - SqlInstance (string): The full SQL Server instance name of the publisher (computer\instance format)
        - TokenID (int): Unique identifier for the tracer token within the publication
        - TokenCreateDate (datetime): The date and time when the tracer token was created and inserted into the publication transaction log
        - PublicationServer (string): The name of the publisher SQL Server instance
        - PublicationDB (string): The name of the database containing the transactional replication publication
        - PublicationName (string): The name of the transactional replication publication
        - PublicationType (string): The type of replication publication (Transactional, Merge, or Snapshot)
        - DistributionServer (string): The name of the distributor SQL Server instance
        - DistributionDB (string): The name of the distribution database on the distributor
        - SubscriberServer (string): The name of the subscriber SQL Server instance receiving the replicated data
        - SubscriberDB (string): The name of the subscription database on the subscriber
        - PublisherToDistributorLatency (timespan or DBNull): Time in seconds for the tracer token to travel from the publisher transaction log to the distributor; may be DBNull if latency has not yet been recorded
        - DistributorToSubscriberLatency (timespan or DBNull): Time in seconds for the tracer token to travel from the distributor to the subscriber; may be DBNull if the token has not yet reached the subscriber
        - TotalLatency (timespan or DBNull): Combined latency (PublisherToDistributorLatency + DistributorToSubscriberLatency); DBNull if either component latency is not yet available

    .EXAMPLE
        PS C:\> Test-DbaReplLatency -SqlInstance sql2008, sqlserver2012

        Return replication latency for all transactional publications for servers sql2008 and sqlserver2012.

    .EXAMPLE
        PS C:\> Test-DbaReplLatency -SqlInstance sql2008 -Database TestDB

        Return replication latency for all transactional publications on server sql2008 for only the TestDB database

    .EXAMPLE
        PS C:\> Test-DbaReplLatency -SqlInstance sql2008 -Database TestDB -PublicationName TestDB_Pub

        Return replication latency for the TestDB_Pub publication for the TestDB database located on the server sql2008.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]] $SqlInstance, #Publisher
        [object[]]$Database,
        [PSCredential]$SqlCredential,
        [object[]]$PublicationName,
        [int]$TimeToLive,
        [switch]$RetainToken,
        [switch]$DisplayTokenHistory,
        [switch]$EnableException
    )
    begin {
        Add-ReplicationLibrary
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($instance in $SqlInstance) {

            # Connect to the publisher
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $publicationNames = Get-DbaReplPublication -SqlInstance $server -Database $Database -SqlCredential $SqlCredentials -Type "Transactional"

            if ($PublicationName) {
                $publicationNames = $publicationNames | Where-Object PublicationName -in $PublicationName
            }


            foreach ($publication in $publicationNames) {

                # Create an instance of TransPublication
                $transPub = New-Object Microsoft.SqlServer.Replication.TransPublication

                $transPub.Name = $publication.PublicationName
                $transPub.DatabaseName = $publication.Database

                # Set the Name and DatabaseName properties for the publication, and set the ConnectionContext property to the connection created in step 1.
                $transsqlconn = New-SqlConnection -SqlInstance $instance -SqlCredential $SqlCredential
                $transPub.ConnectionContext = $transsqlconn

                # Call the LoadProperties method to get the properties of the object. If this method returns false, either the publication properties in Step 3 were defined incorrectly or the publication does not exist.
                if (!$transPub.LoadProperties()) {
                    Stop-Function -Message "LoadProperties() failed. The publication does not exist." -Continue
                }

                # Call the PostTracerToken method. This method inserts a tracer token into the publication's Transaction log.
                $transPub.PostTracerToken() | Out-Null
            }

            ##################################################################################
            ### Determine Latency and validate connections for a transactional publication ###
`           ##################################################################################

            $repServer = New-Object Microsoft.SqlServer.Replication.ReplicationServer
            $sqlconn = New-SqlConnection -SqlInstance $instance -SqlCredential $SqlCredential
            $repServer.ConnectionContext = $sqlconn

            $distributionServer = $repServer.DistributionServer
            $distributionDatabase = $repServer.DistributionDatabase

            # Step 1: Connect to the distributor

            try {
                $distServer = Connect-DbaInstance -SqlInstance $DistributionServer -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $DistributionServer -Continue
            }

            foreach ($publication in $publicationNames) {

                $pubMon = New-Object Microsoft.SqlServer.Replication.PublicationMonitor

                $pubMon.Name = $publication.PublicationName
                $pubMon.DistributionDBName = $distributionDatabase
                $pubMon.PublisherName = $publication.Server
                $pubMon.PublicationDBName = $publication.Database

                $distsqlconn = New-SqlConnection -SqlInstance $DistributionServer -SqlCredential $SqlCredential
                $pubMon.ConnectionContext = $distsqlconn


                # Call the LoadProperties method to get the properties of the object. If this method returns false, either the publication monitor properties in Step 3 were defined incorrectly or the publication does not exist.
                if (!$pubMon.LoadProperties()) {
                    Stop-Function -Message "LoadProperties() failed. The publication does not exist." -Continue
                }

                $tokenList = $pubMon.EnumTracerTokens()

                if (!$DisplayTokenHistory) {
                    $tokenList = $tokenList[0]
                }


                foreach ($token in $tokenList) {

                    $tracerTokenId = $token.TracerTokenId

                    $tokenInfo = $pubMon.EnumTracerTokenHistory($tracerTokenId)

                    $timer = 0

                    $continue = $true

                    while (($tokenInfo.Tables[0].Rows[0].subscriber_latency -eq [System.DBNull]::Value) -and $continue ) {
                        if ($TimeToLive -and ($timer -gt $TimeToLive)) {
                            $continue = $false
                            Stop-Function -Message "TimeToLive has been reached for token: $tracerTokenId" -Continue
                        }

                        Start-Sleep -Seconds 1
                        $timer += 1
                        $tokenInfo = $PubMon.EnumTracerTokenHistory($tracerTokenId)
                    }


                    foreach ($info in $tokenInfo.Tables[0].Rows) {

                        $totalLatency = if (($info.distributor_latency -eq [System.DBNull]::Value) -or ($info.subscriber_latency -eq [System.DBNull]::Value)) {
                            [System.DBNull]::Value
                        } else {
                            ($info.distributor_latency + $info.subscriber_latency)
                        }

                        [PSCustomObject]@{
                            ComputerName                   = $server.ComputerName
                            InstanceName                   = $server.InstanceName
                            SqlInstance                    = $server.SqlInstance
                            TokenID                        = $tracerTokenId
                            TokenCreateDate                = $token.PublisherCommitTime
                            PublicationServer              = $publication.Server
                            PublicationDB                  = $publication.Database
                            PublicationName                = $publication.PublicationName
                            PublicationType                = $publication.Type
                            DistributionServer             = $distributionServer
                            DistributionDB                 = $distributionDatabase
                            SubscriberServer               = $info.subscriber
                            SubscriberDB                   = $info.subscriber_db
                            PublisherToDistributorLatency  = $info.distributor_latency
                            DistributorToSubscriberLatency = $info.subscriber_latency
                            TotalLatency                   = $totalLatency
                        } | Select-DefaultView -ExcludeProperty Type


                        if (!$RetainToken) {

                            $pubMon.CleanUpTracerTokenHistory($tracerTokenId)

                        }
                    }
                }
            }
        }
    }
}