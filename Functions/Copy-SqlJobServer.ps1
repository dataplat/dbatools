
Function Copy-SqlJobServer      {
 <#
            .SYNOPSIS
              Copies ProxyAccounts, JobSchedule, SharedSchedules, AlertSystem, JobCategories, 
			  OperatorCategories AlertCategories, Alerts, TargetServerGroups, TargetServers, 
			  Operators, Jobs, Mail and general SQL Agent settings from one SQL Server Agent 
			  to another. $sourceserver and $destserver are SMO server objects. Ignores -force:
			  does not drop and recreate.

            .EXAMPLE
               Copy-SqlJobServer $sourceserver $destserver  

            .OUTPUTS
                $true if success
                $false if failure
			
        #>
		[cmdletbinding(SupportsShouldProcess = $true)] 
        param(
			[parameter(Mandatory = $true)]
			[object]$Source,
			[parameter(Mandatory = $true)]
			[object]$Destination,
			[System.Management.Automation.PSCredential]$SourceSqlCredential,
			[System.Management.Automation.PSCredential]$DestinationSqlCredential,
			[Switch]$CsvLog
		)
	
PROCESS {
	$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
	$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
	
	Invoke-SMOCheck -SqlServer $sourceserver
	Invoke-SMOCheck -SqlServer $destserver
	
	$source = $sourceserver.name
	$destination = $destserver.name	
	
	if (!(Test-SqlAgent $sourceserver)) { Write-Error "SQL Agent not running on $source. Halting job import."; return }
	if (!(Test-SqlAgent $destserver)) { Write-Error "SQL Agent not running on $destination. Halting job import."; return }
		
	$sourceagent = $sourceserver.jobserver
	$migratedjob = @{}; $skippedjob = @{}
	
	$jobobjects = "ProxyAccounts","JobSchedule","SharedSchedules","AlertSystem","JobCategories","OperatorCategories"
	$jobobjects += "AlertCategories","Alerts","TargetServerGroups","TargetServers","Operators", "Jobs", "Mail"
	
	$errorcount = 0
	foreach ($jobobject in $jobobjects) {
		foreach($agent in $sourceagent.($jobobject)) {		
		$agentname = $agent.name
		If ($Pscmdlet.ShouldProcess($destination,"Adding $jobobject $agentname")) {
				try {
				$sql = $agent.script()	
				$null = $destserver.ConnectionContext.ExecuteNonQuery($sql)
				$migratedjob["$jobobject $agentname"] = "Successfully added"
				Write-Output "$agentname successfully migrated "
				} 
				catch { 
					if ($_.Exception -like '*duplicate*' -or $_.Exception -like '*exist*') {
						Write-Output "$agentname exists at destination"
						$skippedjob.Add("$jobobject $agentname","Skipped. $agentname exists on $destination.") }
					else { $skippedjob["$jobobject $agentname"] = $_.Exception.Message }
				}
			}
		}
	 }
	
	if ($csvlog) {
		$timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
		$csvfilename = "$($sourceserver.name.replace('\','$'))-to-$($destserver.name.replace('\','$'))-$timenow"
		$migratedjob.GetEnumerator() | Sort-Object | Select Name, Value | Export-Csv -Path "$csvfilename-jobs.csv" -NoTypeInformation
		$skippedjob.GetEnumerator() | Sort-Object | Select Name, Value | Export-Csv -Append -Path "$csvfilename-jobs.csv" -NoTypeInformation
	}
}

END {
	$sourceserver.ConnectionContext.Disconnect()
	$destserver.ConnectionContext.Disconnect()
	If ($Pscmdlet.ShouldProcess("console","Showing finished message")) { Write-Output "Job server migration finished" }
}
}