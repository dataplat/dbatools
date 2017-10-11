function Start-DbaRunspace {
<#
	.SYNOPSIS
		Starts a managed runspace
	
	.DESCRIPTION
		Starts a runspace that was registered to dbatools
		Simply registering does not automatically start a given runspace. Only by executing this function will it take effect.
	
	.PARAMETER Name
		The name of the registered runspace to launch
	
	.PARAMETER Runspace
		The runspace to launch. Returned by Get-DbaRunspace
	
	.PARAMETER Silent
		This parameters disables user-friendly warnings and enables the throwing of exceptions.
		This is less user friendly, but allows catching exceptions in calling scripts.
	
	.EXAMPLE
		PS C:\> Start-DbaRunspace -Name 'mymodule.maintenance'
		
		Starts the runspace registered under the name 'mymodule.maintenance'
#>
	[CmdletBinding()]
	Param (
		[Parameter(ValueFromPipeline = $true)]
		[string[]]
		$Name,
		
		[Parameter(ValueFromPipeline = $true)]
		[Sqlcollaborative.Dbatools.Runspace.RunspaceContainer[]]
		$Runspace,
		
		[switch]
		$Silent
	)
	
	process {
		foreach ($item in $Name) {
			# Ignore all output from Get-PSFRunspace - it'll be handled by the second loop
			if ($item -eq "Sqlcollaborative.Dbatools.Runspace.runspacecontainer") { continue }
			
			if ([Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces.ContainsKey($item.ToLower())) {
				try {
					Write-Message -Level Verbose -Message "Starting runspace: <c='em'>$($item.ToLower())</c>" -Target $item.ToLower()
					[Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces[$item.ToLower()].Start()
				}
				catch {
					Stop-Function -Message "Failed to start runspace: <c='em'>$($item.ToLower())</c>" -Silent $Silent -Target $item.ToLower() -Continue
				}
			}
			else {
				Stop-Function -Message "Failed to start runspace: <c='em'>$($item.ToLower())</c> | No runspace registered under this name!" -Silent $Silent -Category InvalidArgument -Tag "fail", "argument", "runspace", "start" -Target $item.ToLower() -Continue
			}
		}
		
		foreach ($item in $Runspace) {
			try {
				Write-Message -Level Verbose -Message "Starting runspace: <c='em'>$($item.Name.ToLower())</c>" -Target $item
				$item.Start()
			}
			catch {
				Stop-Function -Message "Failed to start runspace: <c='em'>$($item.Name.ToLower())</c>" -Silent $Silent -Target $item -Continue
			}
		}
	}
}
