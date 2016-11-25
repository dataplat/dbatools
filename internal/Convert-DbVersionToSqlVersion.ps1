Function Convert-DbVersionToSqlVersion
{
	param (
		[string]$dbversion
	)
	
	switch ($dbversion)
	{
		856 { $dbversion = "SQL Server vNext CTP1" }
		852 { $dbversion = "SQL Server 2016" }
		829 { $dbversion = "SQL Server 2016 Prerelease" }
		782 { $dbversion = "SQL Server 2014" }
		706 { $dbversion = "SQL Server 2012" }
		684 { $dbversion = "SQL Server 2012 CTP1" }
		661 { $dbversion = "SQL Server 2008 R2" }
		660 { $dbversion = "SQL Server 2008 R2" }
		655 { $dbversion = "SQL Server 2008 SP2+" }
		612 { $dbversion = "SQL Server 2005" }
		611 { $dbversion = "SQL Server 2005" }
		539 { $dbversion = "SQL Server 2000" }
		515 { $dbversion = "SQL Server 7.0" }
		408 { $dbversion = "SQL Server 6.5" }
	}
	
	return $dbversion
}