$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Should not munge system databases unless explicitly told to." {
       
        $dbs = @( "master", "model", "tempdb", "msdb" )
        
		It "Should not attempt to remove system databases." {                        
            foreach ($db in $dbs) { 
                $db1 = Get-DbaDatabase -SqlInstance $script:instance1 -Database $db
                Remove-DbaDatabase -SqlInstance $script:instance1 -Database $db
                $db2 = Get-DbaDatabase -SqlInstance $script:instance1 -Database $db
                $db2.Name | Should Be $db1.Name
            } 
        }

        It "Should not take system databases offline or change their status." {
            foreach ($db in $dbs) { 
                $db1 = Get-DbaDatabase -SqlInstance $script:instance1 -Database $db
                Remove-DbaDatabase -SqlInstance $script:instance1 -Database $db 
                $db2 = Get-DbaDatabase -SqlInstance $script:instance1 -Database $db                
                $db2.Status | Should Be $db1.Status
                $db2.IsAccessible | Should Be $db1.IsAccessible                
            } 
        }
    }
    Context "Should remove user databases and return useful errors if it cannot." {
		It "Should remove a non system database." {
			Remove-DbaDatabase -SqlInstance $script:instance1 -Database singlerestore
			Get-DbaProcess -SqlInstance $script:instance1 -Database singlerestore | Stop-DbaProcess
			Restore-DbaDatabase -SqlInstance $script:instance1 -Path C:\github\appveyor-lab\singlerestore\singlerestore.bak -WithReplace
            (Get-DbaDatabase -SqlInstance $script:instance1 -Database singlerestore).IsAccessible | Should Be $true
            Remove-DbaDatabase -SqlInstance $script:instance1 -Database singlerestore
            Get-DbaDatabase -SqlInstance $script:instance1 -Database singlerestore | Should Be $null
        }
	}
}