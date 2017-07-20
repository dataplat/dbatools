Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
Describe "Copy-DbaDatabase Integration Tests" -Tags "IntegrationTests" {
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
	
	foreach ($instance in $Instances) {
		Remove-DbaDatabase -SqlInstance $instance -Confirm:$false -Database singlerestore
	}
	
	Context "Detach, copies and attaches database successfully." {
		It "Should be success" {
			Set-Service BITS -StartupType Automatic
			Get-Service BITS | Start-Service -ErrorAction SilentlyContinue
			$null = Restore-DbaDatabase -SqlInstance localhost -Path C:\github\appveyor-lab\detachattach\detachattach.bak -WithReplace
			
			$results = Copy-DbaDatabase -Source $script:sql2008 -Destination $script:sql2016 -Database detachattach -DetachAttach -Reattach -Force
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