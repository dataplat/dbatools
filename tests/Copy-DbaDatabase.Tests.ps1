Describe "Copy-DbaDatabase Integration Tests" -Tags "Integrationtests" {
    # constants
    $Sql2008R2SP2 = "localhost\sql2008r2sp2"
    $Sql2016 = "localhost\sql2016"
    $Instances = @( $Sql2008R2SP2, $Sql2016 )        
    $BackupLocation = "C:\github\appveyor-lab\singlerestore\singlerestore.bak"    
    $NetworkPath = "C:\temp"

    # cleanup
    foreach ($instance in $Instances) {
        Remove-DbaDatabase -SqlInstance $instance -Confirm:$false -Database singlerestore
    }
    
    # Restore and set owner for Single Restore
    $DatabaseName = ( Restore-DbaDatabase -SqlInstance $Sql2008R2SP2 -Path $BackupLocation ).DatabaseName
    Set-DbaDatabaseOwner -SqlInstance $Sql2008R2SP2 -Database $DatabaseName -TargetLogin sa


    # no matter where I put the import, this stop-message fails.
    Context "Restores database with the same properties." {
        It "Should copy a database and retain its name, recovery model, and status." {
            
            $db1 = Get-DbaDatabase -SqlInstance $Sql2008R2SP2 -Database $DatabaseName

            Copy-DbaDatabase -Source $Sql2008R2SP2 -Destination $Sql2016 -Database $DatabaseName -BackupRestore -NetworkShare $NetworkPath
            
            $db2 = Get-DbaDatabase -SqlInstance $Sql2016 -Database $DatabaseName            
            $db2 | Should Not BeNullOrEmpty
            
            # Compare its valuable.
            $db1.Name | Should Be $db2.Name
            $db1.RecoveryModel | Should Be $db2.RecoveryModel
            $db1.Status | Should be $db2.Status
        }        
    }    
}