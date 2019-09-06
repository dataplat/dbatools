function Test-DbaRepLatency {
    <#
    .SYNOPSIS
        Displays replication latency for all transactional publications for a server or database.

    .DESCRIPTION
        Creates tracer tokens to determine latency between the publisher/distributor and the distributor/subscriber
        for all transactional publications for a server, database, or publication.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Database
        The database(s) to process. If unspecified, all databases will be processed.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER PublicationName
        The publication(s) to process. If unspecified, all publications will be processed.

    .PARAMETER TimeToLive
        How long, in seconds, to wait for a tracer token to complete its journey from the publisher to the subscriber.
        If unspecified, all tracer tokens will take as long as they need to process results.

    .PARAMETER RetainToken
        Retains the tracer tokens created for each publication. If unspecified, all tracer tokens created will be discarded.

    .PARAMETER DisplayTokenHistory
        Displays all tracer tokens in each publication. If unspecified, the current tracer token created will be only token displayed.

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
        https://dbatools.io/Test-DbaRepLatency

    .EXAMPLE
        PS C:\> Test-DbaRepLatency -SqlInstance sql2008, sqlserver2012

        Return replication latency for all transactional publications for servers sql2008 and sqlserver2012.

    .EXAMPLE
        PS C:\> Test-DbaRepLatency -SqlInstance sql2008 -Database TestDB

        Return replication latency for all transactional publications on server sql2008 for only the TestDB database

    .EXAMPLE
        PS C:\> Test-DbaRepLatency -SqlInstance sql2008 -Database TestDB -PublicationName TestDB_Pub

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

    process {

        foreach ($instance in $SqlInstance) {


            # Connect to the publisher
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $publicationNames = Get-DbaRepPublication -SqlInstance $server -Database $Database -SqlCredential $SqlCredentials -PublicationType "Transactional"

            if ($PublicationName) {
                $publicationNames = $publicationNames | Where-Object PublicationName -in $PublicationName
            }


            foreach ($publication in $publicationNames) {

                # Create an instance of TransPublication
                $transPub = New-Object Microsoft.SqlServer.Replication.TransPublication

                $transPub.Name = $publication.PublicationName
                $transPub.DatabaseName = $publication.Database

                # Set the Name and DatabaseName properties for the publication, and set the ConnectionContext property to the connection created in step 1.
                $transPub.ConnectionContext = $server.ConnectionContext.SqlConnectionObject

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

            # Set the Name and DatabaseName properties for the Replication Server, and set the ConnectionContext property to the connection created in step 1.
            $repServer.ConnectionContext = $server.ConnectionContext.SqlConnectionObject

            $distributionServer = $repServer.DistributionServer
            $distributionDatabase = $repServer.DistributionDatabase

            # Step 1: Connect to the distributor

            try {
                $distServer = Connect-SqlInstance -SqlInstance $DistributionServer -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $DistributionServer -Continue
            }

            foreach ($publication in $publicationNames) {

                $pubMon = New-Object Microsoft.SqlServer.Replication.PublicationMonitor

                $pubMon.Name = $publication.PublicationName
                $pubMon.DistributionDBName = $distributionDatabase
                $pubMon.PublisherName = $publication.Server
                $pubMon.PublicationDBName = $publication.Database

                $pubMon.ConnectionContext = $distServer.ConnectionContext.SqlConnectionObject;


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
                            PublicationType                = $publication.PublicationType
                            DistributionServer             = $distributionServer
                            DistributionDB                 = $distributionDatabase
                            SubscriberServer               = $info.subscriber
                            SubscriberDB                   = $info.subscriber_db
                            PublisherToDistributorLatency  = $info.distributor_latency
                            DistributorToSubscriberLatency = $info.subscriber_latency
                            TotalLatency                   = $totalLatency
                        } | Select-DefaultView -ExcludeProperty PublicationType


                        if (!$RetainToken) {

                            $pubMon.CleanUpTracerTokenHistory($tracerTokenId)

                        }

                    }
                }
            }
        }
    }
}