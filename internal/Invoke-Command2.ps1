function Invoke-Command2 {
	[CmdletBinding()]
	param (
		[object]$ComputerName=$env:COMPUTERNAME,
		[object]$Credential,
		[scriptblock]$ScriptBlock,
		[object[]]$ArgumentList,
		[switch]$Silent
	)
	
	try {
		if ([dbavalidate]::IsLocalhost($ComputerName)) {
			if ($Credential) {
				Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -Credential $Credential -ErrorAction Stop
			}
			else {
				Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
			}
			
		}
		else {
			if ($Credential) {
				Invoke-Command -ScriptBlock $ScriptBlock -ComputerName $ComputerName -ArgumentList $ArgumentList -Credential $Credential -ErrorAction Stop |
				Select-Object -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName
			}
			else {
				Invoke-Command -ScriptBlock $ScriptBlock -ComputerName $ComputerName -ArgumentList $ArgumentList -ErrorAction Stop |
				Select-Object -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName
			}
		}
	}
	catch {
		Stop-Function -Message $_ -InnerErrorRecord $_
	}
}