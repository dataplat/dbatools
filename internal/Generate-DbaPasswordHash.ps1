function Generate-DbaPasswordHash {
<#

Articles: http://sqlity.net/en/2460/sql-password-hash/
https://learn-powershell.net/2013/03/25/use-powershell-to-calculate-the-hash-of-a-file/
B93B893C
#>
	Param (
		[object]$Password,
		$SqlMajorVersion,
		[byte[]]$byteSalt
	)
	if ($SqlMajorVersion -lt 11) { 
		$algorithm = 'SHA1' 
		$hashVersion = '0100'
	}
	else { 
		$algorithm = 'SHA512'
		$hashVersion = '0200'
	}
		
	if (!$byteSalt) {
		0 .. 3 | ForEach-Object { $byteSalt += Get-Random -Minimum 0 -Maximum 255 }
	}
	
	[string]$stringSalt = ""
	$byteSalt | ForEach-Object { $stringSalt += ("{0:X}" -f $_).PadLeft(2, "0") }
	
	$enc = [system.Text.Encoding]::Unicode
	if ($Password.GetType().Name -eq 'SecureString') {
		$cred = New-Object System.Management.Automation.PSCredential -ArgumentList 'foo', $Password
		$data = $enc.GetBytes($cred.GetNetworkCredential().Password)
	}
	else {
		$data = $enc.GetBytes($Password) 
	}
	$hash = [Security.Cryptography.HashAlgorithm]::Create($algorithm)
	$bytes = $hash.ComputeHash($data+$byteSalt)
	$hashString = "0x$hashVersion$stringSalt"
	$bytes | ForEach-Object { $hashString += ("{0:X2}" -f $_).PadLeft(2, "0") }
	Return $hashString
}