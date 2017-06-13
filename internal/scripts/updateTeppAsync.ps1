$scriptBlock = {
	#region Utility Functions
	function Get-PriorityServer {
		$res = [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::InstanceAccess.Values | Where-Object -Property LastUpdate -LT (New-Object System.DateTime(1, 1, 1, 1, 1, 1))
		$res | Export-Csv "C:\temp\debug-priority.csv"
		$res
	}
	
	function Get-ActionableServer {
		$res = [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::InstanceAccess.Values | Where-Object -Property LastUpdate -LT ((Get-Date) - ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::TeppUpdateInterval)) | Where-Object -Property LastUpdate -GT ((Get-Date) - ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::TeppUpdateTimeout))
		$res | Export-Csv "C:\temp\debug-regular.csv"
		$res
	}
	
	function Update-TeppCache {
		[CmdletBinding()]
		Param (
			[Parameter(ValueFromPipeline = $true)]
			$ServerAccess
		)
		
		begin {
			
		}
		Process {
			if ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::TeppUdaterStopper) { break }
			
			foreach ($instance in $ServerAccess) {
				if ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::TeppUdaterStopper) { break }
				$server = New-Object Microsoft.SqlServer.Management.Smo.Server($instance.ConnectionObject)
				try {
					$server.ConnectionContext.Connect()
				}
				catch {
					Write-Message -Level Warning -Message "Failed to connect in order to update the Tepp Cache" -ErrorRecord $_ -Silent $true
					continue
				}
				
				$FullSmoName = ([Sqlcollective.Dbatools.Parameter.DbaInstanceParameter]$server).FullSmoName.ToLower()
				
				foreach ($scriptBlock in ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::TeppGatherScriptsFast)) {
					# Workaround to avoid stupid issue with scriptblock from different runspace
					[ScriptBlock]::Create($scriptBlock).Invoke()
				}
				
				foreach ($scriptBlock in ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::TeppGatherScriptsSlow)) {
					# Workaround to avoid stupid issue with scriptblock from different runspace
					[ScriptBlock]::Create($scriptBlock).Invoke()
				}
				
				$instance.LastUpdate = Get-Date
			}
		}
		end {
			
		}
	}
	#endregion Utility Functions
	
	#region Main Execution
	while ($true) {
		if ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::TeppUdaterStopper) { break }
		
		Get-PriorityServer | Update-TeppCache
		
		Get-ActionableServer | Update-TeppCache
		
		Start-Sleep -Seconds 5
	}
	#endregion Main Execution
}

[Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::SetScript($scriptBlock)
if (-not ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::TeppAsyncDisabled -or [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::TeppDisabled)) {
	[Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Start()
}