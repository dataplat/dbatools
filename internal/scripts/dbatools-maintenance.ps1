$scriptBlock = {
	$script:___ScriptName = 'maintenance'
	
	# Import module in a way where internals are available
	Import-Module "$([Sqlcollaborative.Dbatools.dbaSystem.SystemHost]::ModuleBase)\dbatools.psm1"
	
	try {
		#region Main Execution
		while ($true) {
			# This portion is critical to gracefully closing the script
			if ([Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces[$___ScriptName.ToLower()].State -notlike "Running") {
				break
			}
			
			$task = $null
			$tasksDone = @()
			while ($task = [Sqlcollaborative.Dbatools.Maintenance.MaintenanceHost]::GetNextTask($tasksDone)) {
				try { $task.ScriptBlock.Invoke() }
				catch { Write-Message -Silent $false -Level Verbose -Message "[Maintenance] Task '$($task.Name)' failed to execute" -ErrorRecord $_ -FunctionName "task:Maintenance" -Target $task }
				$task.LastExecution = Get-Date
				$tasksDone += $task.Name
			}
			
			Start-Sleep -Seconds 5
		}
		#endregion Main Execution
	}
	catch { }
	finally {
		[Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces[$___ScriptName.ToLower()].SignalStopped()
	}
}

Register-DbaRunspace -ScriptBlock $scriptBlock -Name "maintenance"
Start-DbaRunspace -Name "maintenance"