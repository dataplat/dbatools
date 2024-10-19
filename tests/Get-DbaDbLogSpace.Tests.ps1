param($ModuleName = 'dbatools')

Describe "Get-DbaDbLogSpace" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbLogSpace
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param -Mandatory:$false
            }
            $CommandUnderTest | Should -HaveParameter ExcludeSystemDatabase -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter EnableException -Mandatory:$false
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $db1 = "dbatoolsci_{0}" -f $(Get-Random)
            $dbCreate = ("CREATE DATABASE [{0}]
            GO
            ALTER DATABASE [{0}] MODIFY FILE ( NAME = N'{0}_log', SIZE = 10MB )" -f $db1)
            $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Database master -Query $dbCreate
            $results = Get-DbaDbLogSpace -SqlInstance $global:instance2 -Database $db1
        }
        AfterAll {
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database $db1
        }

        It "Should have correct properties" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have database name of $db1" {
            $results.Database | Should -Contain $db1
        }

        It "Should show correct log file size for $db1" {
            ($results | Where-Object { $_.Database -eq $db1 }).LogSize.Kilobyte | Should -Be 10232
        }

        It "Calculation for space used should work for servers < 2012" -Skip:((Connect-DbaInstance -SqlInstance $global:instance2 -SqlCredential $SqlCredential).versionMajor -ge 11) {
            $db1Result = $results | Where-Object { $_.Database -eq $db1 }
            $db1Result.logspaceused | Should -Be ($db1Result.logsize * ($db1Result.LogSpaceUsedPercent / 100))
        }
    }

    Context "System databases exclusions work" {
        BeforeAll {
            $results = Get-DbaDbLogSpace -SqlInstance $global:instance2 -ExcludeSystemDatabase
        }
        It "Should exclude system databases" {
            $results.Database | Should -Not -BeIn @('model', 'master', 'tempdb', 'msdb')
        }
        It "Should still contain $db1" {
            $results.Database | Should -Contain $db1
        }
    }

    Context "User databases exclusions work" {
        BeforeAll {
            $results = Get-DbaDbLogSpace -SqlInstance $global:instance2 -ExcludeDatabase $db1
        }
        It "Should include system databases" {
            @('model', 'master', 'tempdb', 'msdb') | Should -BeIn $results.Database
        }
        It "Should not contain $db1" {
            $results.Database | Should -Not -Contain $db1
        }
    }

    Context "Piping servers works" {
        BeforeAll {
            $results = $global:instance2 | Get-DbaDbLogSpace
        }
        It "Should have database name of $db1" {
            $results.Database | Should -Contain $db1
        }
    }
}
