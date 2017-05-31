function Invoke-Command2 {
	[CmdletBinding()]
	param (
		[string]$ComputerName,
		[scriptblock]$ScriptBlock,
		[object[]]$ArgumentList
	)
	
	if ($ComputerName -eq $env:COMPUTERNAME) {
		Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
	}
	else {
		Invoke-Command -ScriptBlock $ScriptBlock -ComputerName $ComputerName -ArgumentList $ArgumentList
	}
}