Function Convert-DbVersionToSqlVersion
{
	param (
		[string]$dbversion
	)
	
	$dbversion = switch ($dbversion)
	{
		856 { "SQL Server vNext CTP1" }
		852 { "SQL Server 2016" }
		829 { "SQL Server 2016 Prerelease" }
		782 { "SQL Server 2014" }
		706 { "SQL Server 2012" }
		684 { "SQL Server 2012 CTP1" }
		661 { "SQL Server 2008 R2" }
		660 { "SQL Server 2008 R2" }
		655 { "SQL Server 2008 SP2+" }
		612 { "SQL Server 2005" }
		611 { "SQL Server 2005" }
		539 { "SQL Server 2000" }
		515 { "SQL Server 7.0" }
		408 { "SQL Server 6.5" }
		default { $dbversion }
	}
	
	return $dbversion
}
