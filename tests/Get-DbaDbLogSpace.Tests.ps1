$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'ExcludeSystemDatabase', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $db1 = "dbatoolsci_{0}" -f $(Get-Random)
        $dbCreate = ("CREATE DATABASE [{0}]
        GO
        ALTER DATABASE [{0}] MODIFY FILE ( NAME = N'{0}_log', SIZE = 10MB )" -f $db1)
        $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Database master -Query $dbCreate
    }
    AfterAll {
        Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database $db1
    }

    Context "Command actually works" {
        $results = Get-DbaDbLogSpace -SqlInstance $script:instance2 -Database $db1
        It "Should have correct properties" {
            $results | Should Not BeNullOrEmpty
        }

        It "Should have database name of $db1" {
            $results.Database | Should Contain $db1
        }

        It "Should show correct log file size for $db1" {
            ($results | Where-Object { $_.Database -eq $db1 }).LogSize.Kilobyte | Should Be 10232
        }

        if ((Connect-DbaInstance -SqlInstance $script:instance2 -SqlCredential $SqlCredential).versionMajor -lt 11) {
            It "Calculation for space used should work for servers < 2012" {
                $db1Result = $results | Where-Object { $_.Database -eq $db1 }
                $db1Result.logspaceused | should be ($db1Result.logsize * ($db1Result.LogSpaceUsedPercent / 100))
            }
        }
    }

    Context "System databases exclusions work" {
        $results = Get-DbaDbLogSpace -SqlInstance $script:instance2 -ExcludeSystemDatabase
        It "Should exclude system databases" {
            $results.Database | Should Not Bein ('model', 'master', 'tempdb', 'msdb')
        }
        It "Should still contain $db1" {
            $results.Database | Should Contain $db1
        }
    }

    Context "User databases exclusions work" {
        $results = Get-DbaDbLogSpace -SqlInstance $script:instance2 -ExcludeDatabase db1
        It "Should include system databases" {
            ('model', 'master', 'tempdb', 'msdb') | Should Bein $results.Database
        }
        It "Should not contain $db1" {
            $results.Database | Should Contain $db1
        }
    }

    Context "Piping servers works" {
        $results = $script:instance2 | Get-DbaDbLogSpace
        It "Should have database name of $db1" {
            $results.Database | Should Contain $db1
        }
    }

}