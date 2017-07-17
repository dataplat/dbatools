Describe "Remove-DbaDatabase Integration Tests" -Tags "Integrationtests" {
	Context "Should not attempt to remove system databases and skip them if provided" {
        $sql8 = "localhost"
        $dbs = @( "master", "model", "tempdb",, "msdb" )
        Import-Module dbatools

		It "Should not attempt to remove system databases." {                        
            foreach ($db in $dbs) { 
                $db1 = Get-DbaDatabase -SqlInstance $sql8 -Database $db
                Remove-DbaDatabase -SqlInstance $sql8 -Database $db
                $db2 = Get-DbaDatabase -SqlInstance $sql8 -Database $db
                $db2.Name | Should Be $db1.Name
            } 
        }

        It "Should not take system databases offline or change their status." {
            foreach ($db in $dbs) { 
                $db1 = Get-DbaDatabase -SqlInstance $sql8 -Database $db
                Remove-DbaDatabase -SqlInstance $sql8 -Database $db 
                $db2 = Get-DbaDatabase -SqlInstance $sql8 -Database $db                
                $db2.Status | Should Be $db1.Status
                $db2.IsAccessible | Should Be $db1.IsAccessible                
            } 
        }
        
        It "Should remove an arbitrary database passed to it." { 
            $false | Should be $true
        }
	}
}
