$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	$BackupLocation = "$script:appeyorlabrepo\singlerestore\singlerestore.bak"
	$NetworkPath = "C:\temp"
	
	# cleanup
	foreach ($instance in $Instances) {
		Remove-DbaDatabase -SqlInstance $instance -Confirm:$false -Database singlerestore
	}
	
	# Restore and set owner for Single Restore
	$null = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appeyorlabrepo\singlerestore\singlerestore.bak -WithReplace
	Set-DbaDatabaseOwner -SqlInstance $script:instance1 -Database singlerestore -TargetLogin sa
	
	Context "Restores database with the same properties." {
		It "Should copy a database and retain its name, recovery model, and status." {
			
			Copy-DbaDatabase -Source $script:instance1 -Destination $script:instance2 -Database singlerestore -BackupRestore -NetworkShare $NetworkPath
			
			$db1 = Get-DbaDatabase -SqlInstance $script:instance1 -Database singlerestore
			$db1 | Should Not BeNullOrEmpty
			$db2 = Get-DbaDatabase -SqlInstance $script:instance2 -Database singlerestore
			$db2 | Should Not BeNullOrEmpty
			
			# Compare its valuable.
			$db1.Name | Should Be $db2.Name
			$db1.RecoveryModel | Should Be $db2.RecoveryModel
			$db1.Status | Should be $db2.Status
		}
	}
	
	Context "Doesn't write over existing databases" {
		It "Should just warn" {
			$result = Copy-DbaDatabase -Source $script:instance1 -Destination $script:instance2 -Database singlerestore -BackupRestore -NetworkShare $NetworkPath -WarningVariable warning  3>&1
			$warning | Should Match "exists at destination"
		}
	}
	
	foreach ($instance in $Instances) {
		Remove-DbaDatabase -SqlInstance $instance -Confirm:$false -Database singlerestore
	}
	
	Context "Detach, copies and attaches database successfully." {
		It "Should be success" {
			$null = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appeyorlabrepo\detachattach\detachattach.bak -WithReplace
			$results = Copy-DbaDatabase -Source $script:instance1 -Destination $script:instance2 -Database detachattach -DetachAttach -Reattach -Force -WarningAction SilentlyContinue
			$results.Status | Should Be "Successful"
		}
	}
	
	Context "Database with the same properties." {
		It "should not be null" {
			
			$db1 = (Connect-DbaSqlServer -SqlInstance localhost).Databases['detachattach']
			$db2 = (Connect-DbaSqlServer -SqlInstance localhost\sql2016).Databases['detachattach']
			
			$db1 | Should Not Be $null
			$db2 | Should Not Be $null
			
			$db1.Name | Should Be "detachattach"
			$db2.Name | Should Be "detachattach"
		}
	<#
		It "Name, recovery model, and status should match" {
			# This is crazy
			(Connect-DbaSqlServer -SqlInstance localhost).Databases['detachattach'].Name | Should Be (Connect-DbaSqlServer -SqlInstance localhost\sql2016).Databases['detachattach'].Name
			(Connect-DbaSqlServer -SqlInstance localhost).Databases['detachattach'].Tables.Count | Should Be (Connect-DbaSqlServer -SqlInstance localhost\sql2016).Databases['detachattach'].Tables.Count
			(Connect-DbaSqlServer -SqlInstance localhost).Databases['detachattach'].Status | Should Be (Connect-DbaSqlServer -SqlInstance localhost\sql2016).Databases['detachattach'].Status
			
		}
	}
	
	Context "Clean up" {
		foreach ($instance in $instances) {
			Get-DbaDatabase -SqlInstance $instance -NoSystemDb | Remove-DbaDatabase -Confirm:$false
		}
		#>
	}
	
}