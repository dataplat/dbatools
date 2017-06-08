function Invoke-Command2 {
	[CmdletBinding()]
	param (
		[string]$ComputerName=$env:COMPUTERNAME,
		[object]$Credential,
		[scriptblock]$ScriptBlock,
		[object[]]$ArgumentList
	)
	
	if ([dbavalidate]::IsLocalhost($ComputerName)) {
		if ($Credential) {
			Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -Credential $Credential
		}
		else {
			Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
		}
		
	}
	else {
		if ($Credential) {
			Invoke-Command -ScriptBlock $ScriptBlock -ComputerName $ComputerName -ArgumentList $ArgumentList -Credential $Credential
		}
		else {
			Invoke-Command -ScriptBlock $ScriptBlock -ComputerName $ComputerName -ArgumentList $ArgumentList
		}
	}
}