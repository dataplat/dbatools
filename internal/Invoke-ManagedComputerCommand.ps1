Function Invoke-ManagedComputerCommand
{
<#
.SYNOPSIS
Internal command
	
#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("Server")]
		[dbainstanceparameter]$ComputerName,
		[System.Management.Automation.PSCredential]$Credential,
		[Parameter(Mandatory = $true)]
		[scriptblock]$ScriptBlock,
		[string[]]$ArgumentList,
		[switch]$Silent # Left in for legacy but this command needs to throw
	)
	
	$ComputerName = $ComputerName.ComputerName
	
	Test-RunAsAdmin -ComputerName $ComputerName
	
	$resolved = Resolve-DbaNetworkName -ComputerName $ComputerName
	$ipaddr = $resolved.IpAddress
	$ArgumentList += $ipaddr
		
	[scriptblock]$setupScriptBlock = {
		$ipaddr = $args[$args.GetUpperBound(0)]
		
		# Just in case we go remote, ensure the assembly is loaded
		[void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SqlWmiManagement')
		
		$wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $ipaddr
		$null = $wmi.Initialize()
	}
	
	$prescriptblock = $setupScriptBlock.ToString()
	$postscriptblock = $ScriptBlock.ToString()
	
	$scriptblock = [ScriptBlock]::Create("$prescriptblock  $postscriptblock")
		
	try
	{
		Invoke-Command2 -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -Credential $Credential -ErrorAction Stop
	}
	catch
	{
		try
		{
			Write-Message -Level Verbose -Message "Local connection attempt to $ComputerName failed. Connecting remotely."
			
			# For surely resolve stuff
			$hostname = $resolved.fqdn
			
			Invoke-Command2 -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ComputerName $hostname -ErrorAction Stop
		}
		catch {
			throw "SqlWmi connection failed: $_"
		}
	}
}