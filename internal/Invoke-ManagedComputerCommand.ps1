Function Invoke-ManagedComputerCommand
{
<#
.SYNOPSIS
Internal command
	
#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ComputerName")]
		[dbainstanceparameter]$Server,
		[System.Management.Automation.PSCredential]$Credential,
		[Parameter(Mandatory = $true)]
		[scriptblock]$ScriptBlock,
		[string[]]$ArgumentList,
		[switch]$Silent # Left in for legacy but this command needs to throw
	)
	
	$Server = $Server.ComputerName
	
	Test-RunAsAdmin -ComputerName $Server
	
	$ipaddr = (Test-Connection $server -Count 1 -ErrorAction Stop).Ipv4Address
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
		if ($credential.username -ne $null)
		{
			$result = Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -Credential $Credential -ErrorAction Stop
		}
		else
		{
			$result = Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
		}
		
		Write-Message -Level Verbose -Message "Local connection for $server succeeded"
	}
	catch
	{
		try
		{
			Write-Message -Level Verbose -Message "Local connection attempt to $Server failed. Connecting remotely."
			
			# For surely resolve stuff
			$hostname = [System.Net.Dns]::gethostentry($ipaddr)
			$hostname = $hostname.HostName
			
			if ($credential.username -ne $null)
			{
				$result = Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -Credential $Credential -ComputerName $hostname -ErrorAction Stop
			}
			else
			{
				$result = Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ComputerName $hostname -ErrorAction Stop
			}
		}
		catch{
			throw "SqlWmi connection failed: $_"
		}
	}
	
	$result | Select-Object * -ExcludeProperty PSComputerName, RunSpaceID, PSShowComputerName
}
