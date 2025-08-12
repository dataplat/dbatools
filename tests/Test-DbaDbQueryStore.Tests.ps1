#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Test-DbaDbQueryStore",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command $CommandName
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                'SqlInstance',
                'SqlCredential',
                'Database',
                'ExcludeDatabase',
                'InputObject',
                'EnableException'
            )
        }
        It "Should only contain our specific parameters" {
            $actualParameters = $command.Parameters.Keys | Where-Object { $PSItem -notin "WhatIf", "Confirm" }
            $actualParameters | Should -BeIn $expectedParameters
            $expectedParameters | Should -BeIn $actualParameters
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $dbname = "JESSdbatoolsci_querystore_$(get-random)"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $db = New-DbaDatabase -SqlInstance $server -Name $dbname

        $null = Set-DbaDbQueryStoreOption -SqlInstance $TestConfig.instance2 -Database $dbname -State ReadWrite
        $null = Enable-DbaTraceFlag -SqlInstance $TestConfig.instance2 -TraceFlag 7745
    }
    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname -Confirm:$false
        $null = Disable-DbaTraceFlag -SqlInstance $TestConfig.instance2 -TraceFlag 7745
    }
    Context 'Function works as expected' {
        $svr = Connect-DbaInstance -SqlInstance $TestConfig.instance2

        $results = Test-DbaDbQueryStore -SqlInstance $svr -Database $dbname
        It 'Should return results' {
            $results | Should -Not -BeNullOrEmpty
        }
        It 'Should show query store is enabled' {
            ($results | Where-Object Name -eq 'ActualState').Value | Should -Be 'ReadWrite'
        }
        It 'Should show recommended value for query store is to be enabled' {
            ($results | Where-Object Name -eq 'ActualState').RecommendedValue | Should -Be 'ReadWrite'
        }
        It 'Should show query store meets best practice' {
            ($results | Where-Object Name -eq 'ActualState').IsBestPractice | Should -Be $true
        }
        It 'Should show trace flag  7745 is enabled' {
            ($results | Where-Object Name -eq 'Trace Flag 7745 Enabled').Value | Should -Be 'Enabled'
        }
        It 'Should show trace flag 7745 meets best practice' {
            ($results | Where-Object Name -eq 'Trace Flag 7745 Enabled').IsBestPractice | Should -Be $true
        }
    }

    Context 'Exclude database works' {
        $svr = Connect-DbaInstance -SqlInstance $TestConfig.instance2

        $results = Test-DbaDbQueryStore -SqlInstance $TestConfig.instance2 -ExcludeDatabase $dbname
        It 'Should return results' {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should not return results for $dbname" {
            ($results | Where-Object { $_.Database -eq $dbname }) | Should -BeNullOrEmpty
        }
    }

    Context 'Function works with piping smo server object' {
        $svr = Connect-DbaInstance -SqlInstance $TestConfig.instance2

        $results = $svr | Test-DbaDbQueryStore
        It 'Should return results' {
            $results | Should -Not -BeNullOrEmpty
        }
        It 'Should show query store meets best practice' {
            ($results | Where-Object { $_.Database -eq $dbname -and $_.Name -eq 'ActualState' }).IsBestPractice | Should -Be $true
        }
        It 'Should show trace flag 7745 meets best practice' {
            ($results | Where-Object { $_.Name -eq 'Trace Flag 7745 Enabled' }).IsBestPractice | Should -Be $true
        }
    }
}
