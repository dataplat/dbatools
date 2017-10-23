Function Invoke-SmoCheck
{
<# 
.SYNOPSIS 
Checks for PowerShell SMO version vs SQL Server's SMO version.

#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$SqlServer
	)
	
	if ($script:smocheck -ne $true)
	{
		$script:smocheck = $true
		$smo = (([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.Fullname -like "Microsoft.SqlServer.SMO,*" }).FullName -Split ", ")[1]
		$smo = ([version]$smo.TrimStart("Version=")).Major
		$serverversion = $SqlServer.version.major
		
		if ($serverversion - $smo -gt 1)
		{
			Write-Warning "Your version of SMO is $smo, which is significantly older than $($sqlserver.name)'s version $($SqlServer.version.major)."
			Write-Warning "This may present an issue when migrating certain portions of SQL Server."
			Write-Warning "If you encounter issues, consider upgrading SMO."
		}
	}
}
