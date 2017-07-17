Describe "Copy-DbaDatabase Integration Tests" -Tags "Integrationtests" {
    import-module dbatools -force
    # constants
    $sql8 = "localhost" #"localhost\sql2008r2sp2"
    $sql16 = "localhost\sql2014" #"localhost\sql2016"
    $inst = @( $sql8, $sql16 )        
    $BackupLocation = "E:\backups\test\appveyor-lab\singlerestore\singlerestore.bak" #"C:\github\appveyor-lab\singlerestore\singlerestore.bak"    
    # cleanup
    $inst | % { 
        $Databases = Get-DbaDatabase -SqlInstance $_
        Write-Verbose "Attempting to remove $db from $_"
        if ($Databases.Count -gt 0){
            Remove-DbaDatabase -SqlInstance $_ -Database $Databases
        }        
    }

    # prep
    try { 
        $DatabaseName = ( Restore-DbaDatabase -SqlInstance $sql8 -Path $BackupLocation ).DatabaseName
    }
    catch {        
        throw "Could not restore database."
    }

    # no matter where I put the import, this stop-message fails.
    Context "Restores database with the same properties." {
        It "Should have the same database properties" {
            # Copy it to the second instance.       
            $db1 = Get-DbaDatabase -SqlInstance $sql8 -Database $DatabaseName
            Copy-DbaDatabase -Source $sql8 -Destination $sql16 -Database $DatabaseName -BackupRestore -NetworkShare \\Greybox\e$\backups\test
            $db2 = Get-DbaDatabase -SqlInstance $sql16 -Database $DatabaseName
            $db2 | Should Not BeNullOrEmpty
            # Compare its properties.
            $db1.Name | Should Be $db2.Name
        }        
    }
    Context "" {
        It "Should return true." {
            $false | Should Be $true
        }        
    }
    Context "" {
        It "Should return true." {
            $false | Should Be $true
        }        
    }
}