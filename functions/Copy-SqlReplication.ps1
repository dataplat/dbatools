<#
#$transfer.Options.ContinueScriptingOnError
# replace names
# Load SMO, create server object, test connection, disconnect
[void][Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") 
[void][Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.RMO") 
Microsoft.SqlServer.Rmo
$server = New-Object Microsoft.SqlServer.Management.Smo.Server "sqlserver"
try { $server.ConnectionContext.Connect() } catch { throw "Can't connect to SQL Server." }
Write-Host "Connection succeeded." -ForegroundColor Green

$sourceSqlConn = $server.ConnectionContext.SqlConnectionObject
$distributor = New-Object Microsoft.SqlServer.Replication.ReplicationServer $sourceSqlConn


# Trans - creates pub, add articles, starts snapshot

	
$scriptOptions = [Microsoft.SqlServer.Replication.ScriptOptions]::Creation -bor [Microsoft.SqlServer.Replication.ScriptOptions]::IncludeAll -bxor [Microsoft.SqlServer.Replication.ScriptOptions]::IncludeReplicationJobs 


$scriptargs = [Microsoft.SqlServer.Replication.scriptoptions]::Creation -bor [Microsoft.SqlServer.Replication.scriptoptions]::IncludeArticles `
-bor [Microsoft.SqlServer.Replication.scriptoptions]::IncludeSubscriberSideSubscriptions -bor [Microsoft.SqlServer.Replication.scriptoptions]::IncludeAgentProfiles `
-bor [Microsoft.SqlServer.Replication.scriptoptions]::IncludeChangeDestinationDataTypes -bor [Microsoft.SqlServer.Replication.scriptoptions]::IncludeCreateDistributionAgent `
-bor [Microsoft.SqlServer.Replication.scriptoptions]::IncludeCreateLogreaderAgent -bor [Microsoft.SqlServer.Replication.scriptoptions]::IncludeCreateMergeAgent `
-bor [Microsoft.SqlServer.Replication.scriptoptions]::IncludeCreateQueuereaderAgent -bor [Microsoft.SqlServer.Replication.scriptoptions]::IncludeInstallDistributor `
-bor [Microsoft.SqlServer.Replication.scriptoptions]::IncludeMergeDynamicSnapshotJobs -bor [Microsoft.SqlServer.Replication.scriptoptions]::IncludeMergeJoinFilters `
-bor [Microsoft.SqlServer.Replication.scriptoptions]::IncludeMergePartitions -bor [Microsoft.SqlServer.Replication.scriptoptions]::IncludeMergePublicationActivation `
-bor [Microsoft.SqlServer.Replication.scriptoptions]::IncludePublicationAccesses -bor [Microsoft.SqlServer.Replication.scriptoptions]::IncludePublications`
-bor [Microsoft.SqlServer.Replication.scriptoptions]::IncludePullSubscriptions -bor [Microsoft.SqlServer.Replication.scriptoptions]::IncludeRegisteredSubscribers`
-bor [Microsoft.SqlServer.Replication.scriptoptions]::IncludeReplicationJobs -bor [Microsoft.SqlServer.Replication.scriptoptions]::InstallDistributor

#-bor [Microsoft.SqlServer.Replication.scriptoptions]::IncludePartialSubscriptions
#-bor [Microsoft.SqlServer.Replication.scriptoptions]::IncludeCreateSnapshotAgent 
#-bor [Microsoft.SqlServer.Replication.scriptoptions]::IncludeEnableReplicationDB `
#-bor [Microsoft.SqlServer.Replication.scriptoptions]::IncludeDistributionPublishers `
#-bor  [Microsoft.SqlServer.Replication.scriptoptions]::EnableReplicationDB `
# explore -bor  [Microsoft.SqlServer.Replication.scriptoptions]::IncludeCreateSnapshotAgent `
#-bor  [Microsoft.SqlServer.Replication.scriptoptions]::IncludePublisherSideSubscriptions `

 $ScriptOptions = [Microsoft.SqlServer.Replication.ScriptOptions]::Creation `
                   -bor  [Microsoft.SqlServer.Replication.scriptoptions]::IncludeInstallDistributor `
                   -bor  [Microsoft.SqlServer.Replication.scriptoptions]::EnableReplicationDB `
                   -bor  [Microsoft.SqlServer.Replication.scriptoptions]::IncludePublisherSideSubscriptions `
                   -bor  [Microsoft.SqlServer.Replication.scriptoptions]::IncludeCreateLogreaderAgent `
                   -bor  [Microsoft.SqlServer.Replication.scriptoptions]::IncludeCreateDistributionAgent `
                   -bor  [Microsoft.SqlServer.Replication.scriptoptions]::IncludeCreateMergeAgent `
                   -bor  [Microsoft.SqlServer.Replication.scriptoptions]::IncludeCreateSnapshotAgent `
                   -bor  [Microsoft.SqlServer.Replication.scriptoptions]::IncludePublicationAccesses `
                   -bor  [Microsoft.SqlServer.Replication.scriptoptions]::IncludeArticles `
                   -bor  [Microsoft.SqlServer.Replication.scriptoptions]::IncludeSubscriberSideSubscriptions `
                   -bor  [Microsoft.SqlServer.Replication.scriptoptions]::IncludeGo `
        
#InstallDistributor
$repdbs = $distributor.ReplicationDatabases
foreach ($repdb in $repdbs) {
	if ($repdb.HasPublications) {
	
		foreach ($transpub in $repdb.TransPublications) {
		# TransArticles
		# TransSubscriptions
		$transpub.Script([Microsoft.SqlServer.Replication.scriptoptions]::Creation `			
			-bor  [Microsoft.SqlServer.Replication.scriptoptions]::IncludeCreateLogreaderAgent `
			-bor  [Microsoft.SqlServer.Replication.scriptoptions]::IncludeCreateQueuereaderAgent `
			-bor  [Microsoft.SqlServer.Replication.scriptoptions]::IncludePublicationAccesses `
			-bor  [Microsoft.SqlServer.Replication.scriptoptions]::IncludeArticles `
			-bor  [Microsoft.SqlServer.Replication.scriptoptions]::IncludeSubscriberSideSubscriptions
			)		
			break
		}
		
		foreach ($mergepub in $repdb.MergePublications) {
			$mergepub.Script($scriptargs)
		}
		
	}
	
	if ($repdb.HasPullSubscriptions) {
		foreach ($transsub in $repdb.TransPullSubscriptions) {
			$transsub.Script($scriptargs)
		}
		
		foreach ($mergesub in $repdb.MergePullSubscriptions) {
			$mergesub.Script($scriptargs)
		}
	}
}
#>