Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
Describe "Copy-DbaDatabase Integration Tests" -Tags "Integrationtests" {
	# constants
	$script:sql2008 = "localhost\sql2008r2sp2"
	$script:sql2016 = "localhost\sql2016"
	$Instances = @($script:sql2008, $script:sql2016)
	$BackupLocation = "C:\github\appveyor-lab\singlerestore\singlerestore.bak"
	$NetworkPath = "C:\temp"
	
	# cleanup
	foreach ($instance in $Instances) {
		Remove-DbaDatabase -SqlInstance $instance -Confirm:$false -Database singlerestore
	}
	
	# Restore and set owner for Single Restore
	$null = Restore-DbaDatabase -SqlInstance localhost -Path C:\github\appveyor-lab\singlerestore\singlerestore.bak -WithReplace
	Set-DbaDatabaseOwner -SqlInstance $script:sql2008 -Database singlerestore -TargetLogin sa
	
	Context "Restores database with the same properties." {
		It "Should copy a database and retain its name, recovery model, and status." {
			
			$db1 = Get-DbaDatabase -SqlInstance $script:sql2008 -Database singlerestore
			
			Copy-DbaDatabase -Source $script:sql2008 -Destination $script:sql2016 -Database singlerestore -BackupRestore -NetworkShare $NetworkPath
			
			$db2 = Get-DbaDatabase -SqlInstance $script:sql2016 -Database singlerestore
			$db2 | Should Not BeNullOrEmpty
			
			# Compare its valuable.
			$db1.Name | Should Be $db2.Name
			$db1.RecoveryModel | Should Be $db2.RecoveryModel
			$db1.Status | Should be $db2.Status
		}
	}
	
	Remove-DbaDatabase -SqlInstance $script:sql2016 -Confirm:$false -Database singlerestore
	
	Context "Detach, copies and attaches database with the same properties." {
		It "Should copy a database and retain its name, recovery model, and status. Should also reattach source" {
			Set-Service BITS -StartupType Automatic
			Get-Service BITS | Start-Service -ErrorAction SilentlyContinue
			
			$copy = Copy-DbaDatabase -Source $script:sql2008 -Destination $script:sql2016 -Database singlerestore -DetachAttach -Reattach -Force
			$copy.Status | Should Be "Successful"
			
			# Get it again cuz it was reattached
			$db1 = Get-DbaDatabase -SqlInstance $script:sql2008 -Database singlerestore
			$db1 | Should Not Be $null
			
			$db2 = Get-DbaDatabase -SqlInstance $script:sql2016 -Database singlerestore
			$db2 | Should Not Be $null
						
			# Compare its value.
			$db1.Name | Should Be $db2.Name
			$db1.Tables.Count | Should Be $db2.Tables.Count
			$db1.Status | Should be $db2.Status
			$db1.RecoveryModel | Should be $db2.RecoveryModel
		}
	}
	
	Context "Clean up" {
		foreach ($instance in $instances) {
			Get-DbaDatabase -SqlInstance $instance -NoSystemDb | Remove-DbaDatabase -Confirm:$false
		}
	}
}