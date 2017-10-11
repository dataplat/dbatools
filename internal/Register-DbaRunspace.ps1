function Register-DbaRunspace {
<#
	.SYNOPSIS
		Registers a scriptblock to run in the background.
	
	.DESCRIPTION
		This function registers a scriptblock to run in separate runspace.
		This is different from most runspace solutions, in that it is designed for permanent background tasks that need to be done.
		It guarantees a single copy of the task to run within the powershell process, even when running the same module in many runspaces in parallel.
	
		Updating:
		If this function is called multiple times, targeting the same name, it will update the scriptblock.
		- If that scriptblock is the same as the previous scriptblock, nothing changes
		- If that scriptblock is different from the previous ones, it will be registered, but will not be executed right away!
		  Only after stopping and starting the runspace will it operate under the new scriptblock.
	
	.PARAMETER ScriptBlock
		The scriptblock to run in a dedicated runspace
	
	.PARAMETER Name
		The name to register the scriptblock under.
	
	.PARAMETER Silent
		This parameters disables user-friendly warnings and enables the throwing of exceptions.
		This is less user friendly, but allows catching exceptions in calling scripts.
	
	.EXAMPLE
		PS C:\> Register-DbaRunspace -ScriptBlock $scriptBlock -Name 'mymodule.maintenance'
	
		Registers the script defined in $scriptBlock under the name 'mymodule.maintenance'
		It does not start the runspace yet. If it already exists, it will overwrite the scriptblock without affecting the running script.
	
	.EXAMPLE
		PS C:\> Register-DbaRunspace -ScriptBlock $scriptBlock -Name 'mymodule.maintenance'
		PS C:\> Start-DbaRunspace -Name 'mymodule.maintenance'
	
		Registers the script defined in $scriptBlock under the name 'mymodule.maintenance'
		Then it starts the runspace, running the registered $scriptBlock
#>
	[CmdletBinding(PositionalBinding = $false)]
	param
	(
		[Parameter(Mandatory = $true)]
		[Scriptblock]
		$ScriptBlock,
		
		[Parameter(Mandatory = $true)]
		[String]
		$Name,
		
		[switch]
		$Silent
	)
	
	if ([Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces.ContainsKey($Name.ToLower())) {
		Write-Message -Level Verbose -Message "Updating runspace: <c='Green'>$($Name.ToLower())</c>" -Target $Name.ToLower() -Silent $Silent
		[Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces[$Name.ToLower()].SetScript($ScriptBlock)
	}
	else {
		Write-Message -Level Verbose -Message "Registering runspace: <c='Green'>$($Name.ToLower())</c>" -Target $Name.ToLower() -Silent $Silent
		[Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces[$Name.ToLower()] = New-Object Sqlcollaborative.Dbatools.Runspace.RunspaceContainer($Name.ToLower(), $ScriptBlock)
	}
}
