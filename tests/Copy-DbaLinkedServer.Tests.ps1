$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

try {
	$connstring = "Server=ADMIN:$script:instance1;Trusted_Connection=True"
	$server = New-Object Microsoft.SqlServer.Management.Smo.Server $script:instance1
	$server.ConnectionContext.ConnectionString = $connstring
	$server.ConnectionContext.Connect()
	$server.ConnectionContext.Disconnect()
	Clear-DbaSqlConnectionPool
}
catch {
	Write-Host "DAC not working this round, likely due to Appveyor resources"
	return
}
<#
$dropsql = "EXEC master.dbo.sp_dropserver @server=N'dbatools-localhost', @droplogins='droplogins';
			EXEC master.dbo.sp_dropserver @server=N'dbatools-localhost2', @droplogins='droplogins'"

$createsql = "EXEC master.dbo.sp_addlinkedserver @server = N'dbatools-localhost', @srvproduct=N'SQL Server';
		EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=N'dbatools-localhost',@useself=N'False',@locallogin=NULL,@rmtuser=N'testuser1',@rmtpassword='supfool';
		EXEC master.dbo.sp_addlinkedserver @server = N'dbatools-localhost2', @srvproduct=N'SQL Server';
		EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=N'dbatools-localhost2',@useself=N'False',@locallogin=NULL,@rmtuser=N'testuser1',@rmtpassword='supfool';"
# One more for the road - clearing the connection pool is important for DAC since only one is allowed
Clear-DbaSqlConnectionPool

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Create new linked server" {
		$server1 = Connect-DbaSqlServer -SqlInstance $script:instance1
		$server2 = Connect-DbaSqlServer -SqlInstance $script:instance2
		try {
			$server1.Query($dropsql)
			$server2.Query($dropsql)
		}
		catch {
			# dont care
		}
		
		$server1.Query($createsql)
	}
	
	Context "Copy Credential with the same properties." {
		It "Should copy successfully" {
			$results = Copy-DbaLinkedServer -Source $script:instance1 -Destination $script:instance2 -LinkedServer dbatools-localhost
			foreach ($result in $results) {
				$result.Name | Should Be "dbatools-localhost"
				$result.Status | Should Be "Successful"
			}
		}
		
		It "Should retain its same properties" {
			
			$LinkedServer1 = Get-DbaLinkedServer -SqlInstance $script:instance1 -LinkedServer dbatools-localhost
			$LinkedServer2 = Get-DbaLinkedServer -SqlInstance $script:instance2 -LinkedServer dbatools-localhost
			
			# Compare its value
			$LinkedServer1.Name | Should Be $LinkedServer2.Name
			$LinkedServer1.LinkedServer | Should Be $LinkedServer2.LinkedServer
		}
	}
	Clear-DbaSqlConnectionPool
	Context "No overwrite and cleanup" {
		$results = Copy-DbaLinkedServer -Source $script:instance1 -Destination $script:instance2 -LinkedServer dbatools-localhost -WarningVariable warning 3>&1
		It "Should not attempt overwrite" {
			$warning | Should Match "exists"
			
		}
		
		try {
			$server1.Query($dropsql)
			$server2.Query($dropsql)
		}
		catch {
			# dont care
		}
	}
	Clear-DbaSqlConnectionPool
}
#>