Describe "Get-XpDirTree Unit Tests" -Tag 'Unittests'{
    mock Connect-SqlServer { $true }
    mock Test-DbaSqlPath { $true }
    
    Context "Test Connection and User Rights" {
        It "Should throw on an invalid SQL Connection" {
            #mock Test-SQLConnection {(1..12) | %{[System.Collections.ArrayList]$t += @{ConnectSuccess = $false}}}
            Mock Connect-SQLServer { throw }
            { Get-XpDirTreeRestoreFile -path c:\dummy -sqlserver bad\bad } | Should Throw
        }
        It "Should throw if SQL Server can't see the path" {
            Mock Test-DbaSqlPath { $false }
            { Get-XpDirTreeRestoreFile -path c:\dummy -sqlserver bad\bad } | Should Throw
        }
    }
    Context "Non recursive filestructure" {
        $array = (@{ subdirectory = 'full.bak'; depth = 1; file = 1 },
            @{ subdirectory = 'full2.bak'; depth = 1; file = 1 })
        Mock Invoke-DbaSqlcmd { $array } -ParameterFilter { $Query -and $Query -eq "EXEC master.sys.xp_dirtree 'c:\temp\',1,1;" }
        $results = Get-XpDirTreeRestoreFile -path c:\temp -sqlserver bad\bad
        It "Should return an array of 2 files" {
            $results.count | Should Be 2
        }
        It "Should return a file in c:\temp" {
            $results[0].Fullname | Should BeLike 'c:\temp\*bak'
        }
        It "Should return another file in C:\temp" {
            $results[1].Fullname | Should BeLike 'c:\temp\*bak'
        }
    }
    Context "Recursive Filestructure" {
        $array = (@{ subdirectory = 'full.bak'; depth = 1; file = 1 },
            @{ subdirectory = 'full2.bak'; depth = 1; file = 1 },
            @{ subdirectory = 'recurse'; depth = 1; file = 0 })
        Mock Invoke-DbaSqlcmd { $array } -ParameterFilter { $query -and $query -eq "EXEC master.sys.xp_dirtree 'c:\temp\',1,1;" }
        $array2 = (@{ subdirectory = 'fulllow.bak'; depth = 1; file = 1 },
            @{ subdirectory = 'full2low.bak'; depth = 1; file = 1 })
        Mock Invoke-DbaSqlcmd { $array2 } -ParameterFilter { $query -and $query -eq "EXEC master.sys.xp_dirtree 'c:\temp\recurse\',1,1;" }
        $results = Get-XpDirTreeRestoreFile -path c:\temp -sqlserver bad\bad
        It "Should return array of 4 files - recursion" {
            $results.count | Should Be 4
        }
        It "Should return C:\temp\recurse\fulllow.bak" {
            ($results | Where-Object { $_.Fullname -eq 'C:\temp\recurse\fulllow.bak' } | measure-Object).count | Should be 1
        }
        It "Should return C:\temp\recurse\fulllow.bak" {
            ($results | Where-Object { $_.Fullname -eq 'C:\temp\recurse\full2low.bak' } | measure-Object).count | Should be 1
        }
        It "Should return C:\temp\recurse\fulllow.bak" {
            ($results | Where-Object { $_.Fullname -eq 'C:\temp\full.bak' } | measure-Object).count | Should be 1
        }
        It "Should return C:\temp\recurse\fulllow.bak" {
            ($results | Where-Object { $_.Fullname -eq 'C:\temp\full2.bak' } | measure-Object).count | Should be 1
        }
    }
}
