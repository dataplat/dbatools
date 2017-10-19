$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	BeforeAll {
		$server = Connect-DbaInstance -SqlInstance $script:instance2
		$defaultdata = (Get-DbaDefaultPath -SqlInstance $server).Data
		$dbname = "dbatoolscsi_balance"
		$server.Query("CREATE DATABASE $dbname")
		$server.Query("ALTER DATABASE $dbname ADD FILEGROUP SECONDARYFG")
		$server.Databases.Refresh()
		$db = Get-DbaDatabase -SqlInstance $server -Database $dbname
		$db.Query("ALTER DATABASE $dbname ADD FILE (NAME = secondfile, FILENAME = '$defaultdata\$dbname-secondaryfg.ndf') TO FILEGROUP SECONDARYFG")
		
		$db.Query("CREATE TABLE table1 (ID1 INT IDENTITY PRIMARY KEY, Name1 varchar(10))")
		$db.Query("CREATE TABLE table2 (ID2 INT IDENTITY PRIMARY KEY, Name2 varchar(10)) on SECONDARYFG")
		
		$sqlvalues = New-Object System.Collections.ArrayList
		1 .. 1000 | ForEach-Object { $null = $sqlvalues.Add("('some value')") }
		
		$db.Query("insert into table1 (Name1) Values $($sqlvalues -join ',')")
		$db.Query("insert into table2 (Name2) Values $($sqlvalues -join ',')")
		$db.Query("insert into table2 (Name2) Values $($sqlvalues -join ',')")
		
	}
	AfterAll {
		Invoke-DbaBalanceDataFiles -SqlInstance $server -Database $dbname -RebuildOffline
	}
	
	Context "Disks are properly retreived" {
		$results = Get-DbaDiskSpace -ComputerName $env:COMPUTERNAME
		It -Skip "returns $dbname for Database" {
			$results.Database -eq $dbname | Should Be $true
		}
		It -Skip "returns success" {
			$results.Success | Should Be $true
		}
	}
}