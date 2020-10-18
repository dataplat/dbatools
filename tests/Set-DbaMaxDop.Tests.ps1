$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tag "UnitTests", Set-DbaMaxDop {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'MaxDop', 'InputObject', 'AllDatabases', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }

    Context "Input validation" {
        BeforeAll {
            Mock Stop-Function { } -ModuleName dbatools
        }
        It "Should Call Stop-Function. -Database, -AllDatabases and -ExcludeDatabase are mutually exclusive." {
            Set-DbaMaxDop -SqlInstance $script:instance1 -MaxDop 12 -Database $singledb -AllDatabases -ExcludeDatabase "master" | Should Be
        }
        It "Validates that Stop Function Mock has been called" {
            $assertMockParams = @{
                'CommandName' = 'Stop-Function'
                'Times'       = 1
                'Exactly'     = $true
                'Module'      = 'dbatools'
            }
            Assert-MockCalled @assertMockParams
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        Get-DbaProcess -SqlInstance $script:instance1, $script:instance2 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $singledb = "dbatoolsci_singledb"
        $dbs = "dbatoolsci_lildb", "dbatoolsci_testMaxDop", $singledb
        $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbs | Remove-DbaDatabase -Confirm:$false
        foreach ($db in $dbs) {
            Invoke-DbaQuery -SqlInstance $script:instance1 -Query "CREATE DATABASE $db"
            Invoke-DbaQuery -SqlInstance $script:instance2 -Query "CREATE DATABASE $db"
        }
    }
    AfterAll {
        Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbs | Remove-DbaDatabase -Confirm:$false
        Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbs | Remove-DbaDatabase -Confirm:$false
    }

    Context "Apply to multiple instances" {
        $results = Set-DbaMaxDop -SqlInstance $script:instance1, $script:instance2 -MaxDop 2
        foreach ($result in $results) {
            It 'Returns MaxDop 2 for each instance' {
                $result.CurrentInstanceMaxDop | Should Be 2
            }
        }
    }

    Context "Connects to 2016+ instance and apply configuration to single database" {
        $results = Set-DbaMaxDop -SqlInstance $script:instance2 -MaxDop 4 -Database $singledb
        foreach ($result in $results) {
            It 'Returns 4 for each database' {
                $result.DatabaseMaxDop | Should Be 4
            }
        }
    }

    Context "Connects to 2016+ instance and apply configuration to multiple databases" {
        $results = Set-DbaMaxDop -SqlInstance $script:instance2 -MaxDop 8 -Database $dbs
        foreach ($result in $results) {
            It 'Returns 8 for each database' {
                $result.DatabaseMaxDop | Should Be 8
            }
        }
    }

    Context "Piping from Test-DbaMaxDop works" {
        $results = Test-DbaMaxDop -SqlInstance $script:instance2 | Set-DbaMaxDop -MaxDop 4
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        It 'Command returns output' {
            $results.CurrentInstanceMaxDop | Should Not BeNullOrEmpty
            $results.CurrentInstanceMaxDop | Should Be 4
        }
        It 'Maxdop should match expected' {
            $server.Configuration.MaxDegreeOfParallelism.ConfigValue | Should Be 4
        }
    }

    Context "Piping SqlInstance name works" {
        $results = $script:instance2 | Set-DbaMaxDop -MaxDop 2
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        It 'Command returns output' {
            $results.CurrentInstanceMaxDop | Should Not BeNullOrEmpty
            $results.CurrentInstanceMaxDop | Should Be 2
        }
        It 'Maxdop should match expected' {
            $server.Configuration.MaxDegreeOfParallelism.ConfigValue | Should Be 2
        }
    }
}