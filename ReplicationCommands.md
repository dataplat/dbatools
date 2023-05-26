# Replication Work

## Commands to Create

List to keep track of commands we need and who's working on them, most of the names are being pulled from thin air so if you don't agree with new vs add they can all be discussed\changed.

Meaning of the checkmarks:
- [X] Done
- [ ] not done
- [-] in progress by...


### General

- [X] Get-DbaReplServer
- [X] Export-DbaReplServerSetting

### Distribution

- [X] Get-DbaReplDistributor
- [X] Disable-DbaReplDistributor
- [X] Enable-DbaReplDistributor
- [ ] Set-DbaReplDistributor (updating properties?)

### Publishing

- [-] Get-DbaReplPublisher - Mikey
- [ ] Set-DbaReplPublisher (updating properties?)
- [X] Get-DbaReplPublication -- #TODO: Exists but needs some love
- [X] Disable-DbaReplPublishing
- [X] Enable-DbaReplPublishing
- [X] New-DbaReplPublication - Jess
- [X] Remove-DbaReplPublication

### Articles
- [X] Add-DbaReplArticle - Jess
- [X] Remove-DbaReplArticle - Jess
- [-] Get-DbaReplArticle - Cláudio
- [ ] Set-DbaReplArticle

### Columns
- [-] Get-DbaReplArticleColumn
- [ ] Add-DbaReplArticleColumn
- [ ] Remove-DbaReplArticleColumn

### Subscriptions
- [ ] Get-DbaDbSubscription
- [ ] Set-DbaReplDistributor (update properties)
- [X] New-DbaDbSubscription
- [X] Remove-DbaReplSubscription

### Monitoring\Troubleshooting

- [X] Test-DbaReplLatency
- [ ] Run-DbaReplSnapshotAgent ?
- [ ] Get-DbaReplSnapshotAgentStatus
- [ ] Get-DbaReplLogReaderAgentStatus
- [ ] Test-DbaReplSnapFolder - similar to Test-DbaPath but from replication service account perspective or something similar to check If the share (UNC or Local) is accessible from both, publisher and subscriber side
- [ ] Reinitialise-? - what do we need here
## How to run pester tests locally

```PowerShell
 # run this against fresh containers to setup replication as it would be in gh action
 #.\bin\Replication\Invoke-ReplicationSetup.ps1
 # commented out

 #run the tests -Show All will caus
 invoke-pester .\tests\gh-actions-repl.ps1

```

## Testing

Some additional scenarios for us to test commands against.

- how the commands work when we have a "third site" involved , i mean if  we have the distribution db not on the Publication-Server and not on the Subscriber-Server (thats not so common, but it is a thing imo) - I saw some unusual behaviour with replcation commands when the setup is with a seperate Distribution-DB-Server.

## Questions

- Should parameter be `PublicationType` or `Type` and `PublicationName` or `Name`
