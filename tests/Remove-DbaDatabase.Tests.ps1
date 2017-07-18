Describe "Remove-DbaDatabase Integration Tests" -Tags "Integrationtests" {
	Context "Should not attempt to remove system databases and skip them if provided" {
        $Sql2008 = "localhost\sql2008r2sp2"
        $dbs = @( "master", "model", "tempdb", "msdb" )
        
		It "Should not attempt to remove system databases." {                        
            foreach ($db in $dbs) { 
                $db1 = Get-DbaDatabase -SqlInstance $Sql2008 -Database $db
                Remove-DbaDatabase -SqlInstance $Sql2008 -Database $db
                $db2 = Get-DbaDatabase -SqlInstance $Sql2008 -Database $db
                $db2.Name | Should Be $db1.Name
            } 
        }

        It "Should not take system databases offline or change their status." {
            foreach ($db in $dbs) { 
                $db1 = Get-DbaDatabase -SqlInstance $Sql2008 -Database $db
                Remove-DbaDatabase -SqlInstance $Sql2008 -Database $db 
                $db2 = Get-DbaDatabase -SqlInstance $Sql2008 -Database $db                
                $db2.Status | Should Be $db1.Status
                $db2.IsAccessible | Should Be $db1.IsAccessible                
            } 
        }               
	}
}
