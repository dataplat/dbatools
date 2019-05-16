function New-DbaRepSubscriber {
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

    .PARAMETER subType
        The type of subscription e.g. PULL

    .PARAMETER subSyncType
        The subscription sync type. e.g. backup, snapshot, none


    .NOTES
        Tags: Replication
        Author: Gareth Newman

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaRepSubscriber

    .EXAMPLE
        PS C:\> New-DbaRepSubscriber -publisherName "b3457" -subscriberName "b3457" -publicationName "avworkspub1" -pubDatabaseName "AdventureWorks2012" -subDatabaseName "replicatedAdventureWorks2012" -subSyncType "none"

        Creates a new subscription to "stackpub1" on server1\dev2016 to server2\dev2016 with a subscription sync type of none.
        The published database is StackOverflow2010 on server1\dev2016, the subscriber database is repStackOverflow2010 on server2\dev2016.

    #>
    Param(
        [Parameter(Mandatory)]
        $publisherName,
        $subscriberName,
        $publicationName,
        $pubDatabaseName,
        $subDatabaseName,
        $subType,
        $subSyncType
    )

    # create the server connection object
    $srv = New-Object Microsoft.SqlServer.Management.Smo.Server $publisherName

    # create the PULL replication subscription object
    $ts = New-Object Microsoft.SqlServer.Replication.TransSubscription

    # set the replication object connection to the server connection
    $ts.ConnectionContext = $srv.ConnectionContext.SqlConnectionObject

    # set parameters for PULL subscription object
    $ts.SubscriberName = $subscriberName
    $ts.PublicationName = $publicationName
    $ts.DatabaseName = $pubDatabaseName
    $ts.SubscriptionDBName = $subDatabaseName
    $ts.SyncType = $subSyncType

    # create the subscription on the publisher
    $ts.Create()
}