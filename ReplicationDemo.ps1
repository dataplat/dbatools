# dbatools 💜 dbatools

##############################
# create docker environment
##############################
# create a shared network
docker network create localnet

# Expose engines and setup shared path for migrations
docker run -p 2500:1433  --volume shared:/shared:z --name mssql1 --hostname mssql1 --network localnet -d dbatools/sqlinstance
docker run -p 2600:1433 --volume shared:/shared:z --name mssql2 --hostname mssql2 --network localnet -d dbatools/sqlinstance2

# create the repl folder
docker exec mssql1 mkdir /var/opt/mssql/ReplData

# also need these folders for setting up replication
docker exec mssql1 mkdir /shared/data /shared/repldata

##############################

# import out version of the module
cd C:\GitHub\DMM-GitHub\dbatools
Import-Module .\dbatools.psd1

# lets save the password for connecting to containers because I'm lazy
$securePassword = ('dbatools.IO' | ConvertTo-SecureString -AsPlainText -Force)
$credential = New-Object System.Management.Automation.PSCredential('sqladmin', $securePassword)

$PSDefaultParameterValues = @{
    "*:SqlCredential"            = $credential
    "*:DestinationCredential"    = $credential
    "*:DestinationSqlCredential" = $credential
    "*:SourceSqlCredential"      = $credential
    "*:PublisherSqlCredential"   = $credential
}

# what do we have so far
Get-DbaReplServer -SqlInstance mssql1
Get-DbaReplDistributor -SqlInstance mssql1
Get-DbaReplPublisher -SqlInstance mssql1

# enable distribution
Enable-DbaReplDistributor -SqlInstance mssql1

# enable publishing
Enable-DbaReplPublishing -SqlInstance mssql1

# create a transactional publication using splat format
$pub = @{
    SqlInstance     = 'mssql1'
    Database        = 'pubs'
    PublicationName = 'testPub'
    Type            = 'Transactional'
}
New-DbaReplPublication @pub

# add an article to the publication
$article = @{
    SqlInstance     = 'mssql1'
    Database        = 'pubs'
    PublicationName = 'testpub'
    Name            = 'authors'
}
Add-DbaReplArticle @article

# create a pubs database on mssql2 to replicate to
New-DbaDatabase -SqlInstance mssql2 -Name pubs

# if you don't the New-DbaReplSubscription command will create the database for you

# add a subscription to the publication
$sub = @{
    SqlInstance               = 'mssql2'
    Database                  = 'pubs'
    PublicationDatabase       = 'pubs'
    PublisherSqlInstance      = 'mssql1'
    PublicationName           = 'testpub'
    Type                      = 'Push'
    SubscriptionSqlCredential = $credential

}
New-DbaReplSubscription @sub

# creates the snapshot job with a daily schedule at 8am - is that expected? good default?
# should adding a subscription kick off snapshot? should that be an param -StartSnapshotNow -- yes
    # create that without a schedule by default maybe a param for a schedule
    #

# stats on the subscription - in the distribution database
 # could we make a command to get stats





 ## when adding an article - we need the options
  # - action if name is in use 'drop existing object and create new'
  # copy nonclusterd indexes
    # nuno
