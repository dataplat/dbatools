$scriptBlock = {
	$script:___ScriptName = 'maintenance'
	
	try {
		#region Main Execution
		while ($true) {
			# This portion is critical to gracefully closing the script
			if ([Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces[$___ScriptName.ToLower()].State -notlike "Running") {
				break
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