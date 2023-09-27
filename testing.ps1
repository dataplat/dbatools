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
# import our working module
##############################
Import-Module .\dbatools.psd1 -Force
Get-module dbatools*

##############################
# create alias
##############################
New-DbaClientAlias -ServerName 'localhost,2500' -Alias mssql1
New-DbaClientAlias -ServerName 'localhost,2600' -Alias mssql2


##############################
# save the password for ease
##############################
$securePassword = ('dbatools.IO' | ConvertTo-SecureString -AsPlainText -Force)
$credential = New-Object System.Management.Automation.PSCredential('sqladmin', $securePassword)

$PSDefaultParameterValues = @{
    "*:SqlCredential"            = $credential
    "*:DestinationCredential"    = $credential
    "*:DestinationSqlCredential" = $credential
    "*:SourceSqlCredential"      = $credential
    "*:PublisherSqlCredential"   = $credential
}


##############################
# change silly defaults
##############################
Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true  -PassThru | Register-DbatoolsConfig #-Scope SystemMandatory
Set-DbatoolsConfig -FullName sql.connection.EncryptConnection -Value optional -PassThru | Register-DbatoolsConfig #-Scope SystemMandatory

##############################
# test things :)
##############################


## already existing commands
<#
Get-DbaReplServer
Get-DbaReplDistributor
Get-DbaReplPublication
Test-DbaReplLatency

Export-DbaReplServerSetting
#>

$sqlInstance = Connect-DbaInstance -SqlInstance mssql1

Get-DbaReplServer -SqlInstance mssql1
Get-DbaReplDistributor -SqlInstance mssql1
Get-DbaReplPublication -SqlInstance mssql1

# enable\disable distribution
Enable-DbaReplDistributor -SqlInstance mssql1
Disable-DbaReplDistributor -SqlInstance  mssql1

Get-DbaReplDistributor -SqlInstance

# enable publishing
Enable-DbaReplPublishing -SqlInstance mssql1
Disable-DbaReplPublishing -SqlInstance mssql1

# add a transactional publication
$pub = @{
    SqlInstance     = 'mssql1'
    Database        = 'pubs'
    PublicationName = 'testPub'
    Type            = 'Transactional'

}
New-DbaReplPublication @pub -verbose



# add a merge publication
$pub = @{
    SqlInstance     = 'mssql1'
    Database        = 'pubs'
    PublicationName = 'mergey'
    Type            = 'Merge'

}
New-DbaReplPublication @pub

# add a snapshot publication
$pub = @{
    SqlInstance     = 'mssql1'
    Database        = 'pubs'
    PublicationName = 'snappy'
    Type            = 'Snapshot'

}
New-DbaReplPublication @pub


# add an article

$article = @{
    SqlInstance     = 'mssql1'
    Database        = 'pubs'
    PublicationName = 'testpub'
    Name            = 'publishers'
    Filter          = "city = 'seattle'"
}
Add-DbaReplArticle @article

$article = @{
    SqlInstance     = 'mssql1'
    Database        = 'ReplDb'
    PublicationName = 'testtrans'
    Name            = 'ReplicateMe'
}
Add-DbaReplArticle @article -EnableException

# mergey
$article = @{
    SqlInstance     = 'mssql1'
    Database        = 'pubs'
    PublicationName = 'Mergey'
    Name            = 'publishers'
    #Filter          = "city = 'seattle'"  ## not working?
}
Add-DbaReplArticle @article

# snappy
$article = @{
    SqlInstance     = 'mssql1'
    Database        = 'pubs'
    PublicationName = 'snappy'
    Name            = 'publishers'
}
Add-DbaReplArticle @article


# remove an article
$article = @{
    SqlInstance     = 'mssql1'
    Database        = 'pubs'
    PublicationName = 'testpub'
    Name            = 'publishers'
}
Remove-DbaReplArticle @article

# remove an article
$article = @{
    SqlInstance     = 'mssql1'
    Database        = 'pubs'
    PublicationName = 'Mergey'
    Name            = 'publishers'
}
Remove-DbaReplArticle @article



## remove pubs
$pub = @{
    SqlInstance     = 'mssql1'
    Database        = 'ReplDb'
    Name            = 'Snappy'
}
Remove-DbaReplPublication @pub
## remove pubs
$pub = @{
    SqlInstance     = 'mssql1'
    Database        = 'ReplDb'
    Name            = 'TestPub'
}
Remove-DbaReplPublication @pub
## remove pubs
$pub = @{
    SqlInstance     = 'mssql1'
    Database        = 'ReplDb'
    Name            = 'Mergey'
}
Remove-DbaReplPublication @pub



# add subscriptions.

#transactional
$sub = @{
    SqlInstance               = 'mssql2'
    Database                  = 'pubs'
    PublicationDatabase       = 'pubs'
    PublisherSqlInstance      = 'mssql1'
    PublicationName           = 'testpub'
    Type                      = 'Push'
    SubscriptionSqlCredential = $credential

}
New-DbaReplSubscription @sub -enableexception

#merge
$sub = @{
    SqlInstance               = 'mssql2'
    Database                  = 'Mergeypubs'
    PublicationDatabase       = 'pubs'
    PublisherSqlInstance      = 'mssql1'
    PublicationName           = 'Mergey'
    Type                      = 'Push'
    SubscriptionSqlCredential = $credential

}
New-DbaReplSubscription @sub

#snapshot
$sub = @{
    SqlInstance               = 'mssql2'
    Database                  = 'Snappypubs'
    PublicationDatabase       = 'pubs'
    PublisherSqlInstance      = 'mssql1'
    PublicationName           = 'Snappy'
    Type                      = 'Push'
    SubscriptionSqlCredential = $credential
}
New-DbaReplSubscription @sub


# remove subscriptions
$sub = @{
    SqlInstance          = 'mssql2'
    SubscriptionDatabase = 'pubs'
    PublisherSqlInstance = 'mssql1'
    PublicationDatabase  = 'pubs'
    PublicationName      = 'testPub'
}
Remove-DbaReplSubscription @sub

$sub = @{
    SqlInstance          = 'mssql2'
    SubscriptionDatabase = 'Mergeypubs'
    PublisherSqlInstance = 'mssql1'
    PublicationDatabase  = 'pubs'
    PublicationName      = 'Mergey'
}
Remove-DbaReplSubscription @sub

$sub = @{
    SqlInstance          = 'mssql2'
    PublisherSqlInstance = 'mssql1'
    PublicationName      = 'snappy'
    PublicationDatabase  = 'pubs'
    SubscriptionDatabase = 'Snappypubs'
}
Remove-DbaReplSubscription @sub

# TODO: Does the schema exist on the subscriber?
<#
// Ensure that we create the schema owner at the Subscriber.
article.SchemaOption |= CreationScriptOptions.Schema;
#>