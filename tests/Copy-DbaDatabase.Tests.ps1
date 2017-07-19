Describe "Copy-DbaDatabase Integration Tests" -Tags "Integrationtests" {
    # constants
    $sql2008 = "localhost\sql2008r2sp2"
    $sql2016 = "localhost\sql2016"
    $Instances = @( $sql2008, $sql2016 )        
    $BackupLocation = "C:\github\appveyor-lab\singlerestore\singlerestore.bak"    
    $NetworkPath = "C:\temp"

    # cleanup
    foreach ($instance in $Instances) {
        Remove-DbaDatabase -SqlInstance $instance -Confirm:$false -Database singlerestore
    }
    
    # Restore and set owner for Single Restore
    $DatabaseName = ( Restore-DbaDatabase -SqlInstance $sql2008 -Path $BackupLocation ).DatabaseName
    Set-DbaDatabaseOwner -SqlInstance $sql2008 -Database $DatabaseName -TargetLogin sa

    Context "Restores database with the same properties." {
        It "Should copy a database and retain its name, recovery model, and status." {
            
            $db1 = Get-DbaDatabase -SqlInstance $sql2008 -Database $DatabaseName

            Copy-DbaDatabase -Source $sql2008 -Destination $sql2016 -Database $DatabaseName -BackupRestore -NetworkShare $NetworkPath
            
            $db2 = Get-DbaDatabase -SqlInstance $sql2016 -Database $DatabaseName            
            $db2 | Should Not BeNullOrEmpty
            
            # Compare its valuable.
            $db1.Name | Should Be $db2.Name
            $db1.RecoveryModel | Should Be $db2.RecoveryModel
            $db1.Status | Should be $db2.Status
        }        
    }    
    
    Remove-DbaDatabase -SqlInstance $sql2016 -Confirm:$false -Database singlerestore
    
	Context "Detach, copies and attaches database with the same properties." {
		It "Should copy a database and retain its name, recovery model, and status. Should also reattach source" {
			Set-Service BITS -StartupType Automatic
			Get-Service BITS | Start-Service -ErrorAction SilentlyContinue
			$db1 = Get-DbaDatabase -SqlInstance $sql2008 -Database $databasename
			
			Copy-DbaDatabase -Source $sql2008 -Destination $sql2016 -Database $databasename -DetachAttach -Reattach -Force
			
			$db2 = Get-DbaDatabase -SqlInstance $sql2016 -Database $databasename
			$db2 | Should Not BeNullOrEmpty
			
			# Get it again cuz it was reattached
			$db1 = Get-DbaDatabase -SqlInstance $sql2008 -Database $databasename
			
			# Compare its value.
			$db1.Name | Should Be $db2.Name
			$db1.RecoveryModel | Should Be $db2.RecoveryModel
			$db1.Status | Should be $db2.Status
		}
	}
	
	Context "Clean up" {
		foreach ($instance in $instances) {
			Get-DbaDatabase -SqlInstance $instance -NoSystemDb | Remove-DbaDatabase -Confirm:$false
		}
    }
}