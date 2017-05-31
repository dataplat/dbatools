function Invoke-Command2 {
	[CmdletBinding()]
	param (
		[string]$ComputerName,
		[scriptblock]$ScriptBlock,
		[object[]]$ArgumentList
	)
	
	if ([dbavalidate]::IsLocalhost($ComputerName)) {
		Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
	}
	else {
		Invoke-Command -ScriptBlock $ScriptBlock -ComputerName $ComputerName -ArgumentList $ArgumentList
	}
}