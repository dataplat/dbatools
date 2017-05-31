function Invoke-Command2 {
	[CmdletBinding()]
	param (
		[string]$ComputerName,
		[scriptblock]$ScriptBlock
	)
	
	if ($ComputerName -eq $env:COMPUTERNAME) {
		Invoke-Command -ScriptBlock $ScriptBlock
	}
	else {
		Invoke-Command -ScriptBlock $ScriptBlock -ComputerName $ComputerName
	}
}