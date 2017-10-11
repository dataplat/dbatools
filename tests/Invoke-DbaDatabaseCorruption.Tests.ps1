$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tags "UnitTests" {
	Context "Validating Database Input" {
		Invoke-DbaDatabaseCorruption -SqlInstance $script:instance1 -Database "master" -WarningAction SilentlyContinue -WarningVariable systemwarn
		It "Should not allow you to corrupt system databases."{
			$systemwarn -match 'may not corrupt system databases' | Should Be $true
		}
		It "Should fail if more than one database is specified" {
			{ Invoke-DbaDatabaseCorruption -SqlInstance $script:instance1 -Database "Database1", "Database2" -Silent } | Should Throw
		}
	}
	
	Context "It's Confirm impact should be high" {
		$command = Get-Command Invoke-DbaDatabaseCorruption
		$metadata = [System.Management.Automation.CommandMetadata]$command
		$metadata.ConfirmImpact | Should Be 'High'
	}
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	BeforeAll {
		$dbname = "dbatoolsci_InvokeDbaDatabaseCorruptionTest"
		$Server = Connect-DbaInstance -SqlInstance $script:instance1
		$TableName = "Example"
		# Need a clean empty database
		$null = $Server.Query("Create Database [$dbname]")
		$db = Get-DbaDatabase -SqlInstance $Server -Database $dbname
	}
	
	AfterAll {
		# Cleanup
		Remove-DbaDatabase -SqlInstance $Server -Database $dbname -Confirm:$false
	}
	
	It "Require at least a single table in the database specified" {
		{ Invoke-DbaDatabaseCorruption -SqlInstance $server -Database $dbname -Silent } | Should Throw
	}
	
	# Creating a table to make sure these are failing for different reasons
	It "Fail if the specified table does not exist" {
		{ Invoke-DbaDatabaseCorruption -SqlInstance $server -Database $dbname -Table "DoesntExist$(New-Guid)" -Silent } | Should Throw
	}
	
	$null = $db.Query("
		CREATE TABLE dbo.[$TableName] (id int); 
		INSERT dbo.[Example] 
		SELECT top 1000 1 
		FROM sys.objects")	
	
	It "Corrupt a single database" {
		Invoke-DbaDatabaseCorruption -SqlInstance $script:instance1 -Database $dbname -Confirm:$false | Select-Object -ExpandProperty Status | Should be "Corrupted"
	}
	
	It "Causes DBCC CHECKDB to fail" {
		$result = Start-DbccCheck -Server $Server -dbname $dbname
		$result | Should Not Be 'Success'
	}
}