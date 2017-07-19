Describe "Remove-DbaDatabase Integration Tests" -Tags "Integrationtests" {
	Context "Should not attempt to remove system databases and skip them if provided" {
        $sql2008 = "localhost"
        $dbs = @( "master", "model", "tempdb", "msdb" )
        
		It "Should not attempt to remove system databases." {                        
            foreach ($db in $dbs) { 
                $db1 = Get-DbaDatabase -SqlInstance $sql2008 -Database $db
                Remove-DbaDatabase -SqlInstance $sql2008 -Database $db
                $db2 = Get-DbaDatabase -SqlInstance $sql2008 -Database $db
                $db2.Name | Should Be $db1.Name
            } 
        }

        It "Should not take system databases offline or change their status." {
            foreach ($db in $dbs) { 
                $db1 = Get-DbaDatabase -SqlInstance $sql2008 -Database $db
                Remove-DbaDatabase -SqlInstance $sql2008 -Database $db 
                $db2 = Get-DbaDatabase -SqlInstance $sql2008 -Database $db                
                $db2.Status | Should Be $db1.Status
                $db2.IsAccessible | Should Be $db1.IsAccessible                
            } 
        }
        
        It "Should remove a non system database when asked to." {
            Restore-DbaDatabase -SqlInstance $sql2008 -Path C:\github\appveyor-lab\singlerestore\singlerestore.bak
            Remove-DbaDatabase -SqlInstance $sql2008 -Database singlerestore
            $db = Get-DbaDatabase -Database singlerestore
            $db | Should Be NullOrEmpty
        }
	}
}
