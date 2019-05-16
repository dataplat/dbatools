function Add-DbaRepPushSubscription {
    <#
    .SYNOPSIS
        Adds a new subscriber to an existing publication

    .DESCRIPTION
        Creates a new replication subscription to the existing specified publication

    .PARAMETER publisherName
        The target SQL Server(s) which is the publisher.

    .PARAMETER subscriberName
        The target SQL Server(s) which is the subscriber.

    .PARAMETER publicationName
        The name of the publication on the publisher.

    .PARAMETER pubDatabaseName
        The name of the publications database on the publisher.

    .PARAMETER subDatabaseName
        The name of the database on the subscriber.

    .PARAMETER subSyncType
        The subscription sync type. e.g. backup, snapshot, none


    .NOTES
        Tags: Replication
        Author: Gareth Newman

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Add-DbaRepPushSubscription

    .EXAMPLE
        PS C:\> Add-DbaRepPushSubscription -publisherName "server1\dev2016" -subscriberName "server2\dev2016" -publicationName "avworkspub1" -pubDatabaseName "AdventureWorks2012" -subDatabaseName "replicatedAdventureWorks2012" -subSyncType "none"

        Creates a new subscription to "avworkspub1" on server1\dev2016 to server2\dev2016 with a subscription sync type of none.
        The published database is AdventureWorks2012 on server1\dev2016, the subscriber database is replicatedAdventureWorks2012 on server2\dev2016.

    #>
    Param(
        [Parameter(Mandatory)]
        $publisherName,
        $subscriberName,
        $publicationName,
        $pubDatabaseName,
        $subDatabaseName,
        $subSyncType
    )

    # create the server connection object
    try {
        $srv = New-Object Microsoft.SqlServer.Management.Smo.Server $publisherName
    } catch {
        Stop-Function -Message "Error occurred while establishing connection to $publisherName" -Category ConnectionError -ErrorRecord $_ -Target $publisherName -Continue
    }


    # create the PULL replication subscription object
    try{
        $ts = New-Object Microsoft.SqlServer.Replication.TransSubscription
    } catch {
        Stop-Function -Message "Error occurred creating the replication object" -Continue
    }

    # set the replication object connection to the server connection
    try {
        $ts.ConnectionContext = $srv.ConnectionContext.SqlConnectionObject

        # set parameters for PULL subscription object
        $ts.SubscriberName = $subscriberName
        $ts.PublicationName = $publicationName
        $ts.DatabaseName = $pubDatabaseName
        $ts.SubscriptionDBName = $subDatabaseName
        $ts.SyncType = $subSyncType

    } catch {
        Stop-Function -Message "Error occurred setting up the replication object" -Continue
    }

    # create the subscription on the publisher
    try {
        $ts.Create()
    } catch {
        Stop-Function -Message "Error occurred creating the subscription" -Continue
    }


}