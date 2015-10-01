Function Copy-SqlServerTrigger {
 <#
            .SYNOPSIS
             Copies server triggers one by one. If trigger with same name exists on destination, it will
			 not be dropped and recreated unless -force is used.
			
        #>
		[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess = $true)] 
        param(
			[parameter(Mandatory = $true)]
			[object]$Source,
			[parameter(Mandatory = $true)]
			[object]$Destination,
			[System.Management.Automation.PSCredential]$SourceSqlCredential,
			[System.Management.Automation.PSCredential]$DestinationSqlCredential,
			[switch]$force
		)
	
PROCESS {
	$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
	$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential

	$source = $sourceserver.name
	$destination = $destserver.name	
	
	if (!(Test-SqlSa -SqlServer $sourceserver -SqlCredential $SourceSqlCredential)) { throw "Not a sysadmin on $source. Quitting." }
	if (!(Test-SqlSa -SqlServer $destserver -SqlCredential $DestinationSqlCredential)) { throw "Not a sysadmin on $destination. Quitting." }
	
	$triggers = $sourceserver.Triggers
	$desttriggers = $destserver.Triggers
	
	foreach ($trigger in $triggers) {
		if ($desttriggers.name -contains $trigger.name) {
			if ($force -eq $false) {
				Write-Warning "Server trigger $($trigger.name) exists at destination. Use -Force to drop and migrate."
			} else {
				If ($Pscmdlet.ShouldProcess($destination,"Dropping server trigger $($trigger.name) and recreating")) {
					try {
						Write-Output "Dropping server trigger $($trigger.name)"
						$destserver.triggers[$trigger.name].Drop()
						Write-Output "Copying server trigger $($trigger.name)"
						$destserver.ConnectionContext.ExecuteNonQuery($trigger.Script()) | Out-Null
					} catch { Write-Exception $_  }
				}
			}
		} else {
			If ($Pscmdlet.ShouldProcess($destination,"Creating server trigger $($trigger.name)")) {
				try { 
					Write-Output "Copying server trigger $($trigger.name)"
					$destserver.ConnectionContext.ExecuteNonQuery($trigger.Script()) | Out-Null
				 } catch {
					Write-Exception $_ 
				}
			}
		}
	}
}

END {
	$sourceserver.ConnectionContext.Disconnect()
	$destserver.ConnectionContext.Disconnect()
	If ($Pscmdlet.ShouldProcess("console","Showing finished message")) { Write-Output "Server trigger migration finished" }
}
}