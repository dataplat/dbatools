<#
    The below statement stays in for every test you build.
#>
$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

<#
    Unit test is required for any command added
#>
Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('WhatIf', 'Confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'ExcludeSystemSp', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
# Get-DbaNoun
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $procName = ("dbatools_{0}" -f $(Get-Random))
        $server.Query("CREATE PROCEDURE $procName AS SELECT 1", 'tempdb')
    }
    AfterAll {
        $null = $server.Query("DROP PROCEDURE $procName", 'tempdb')
    }

    Context "Command actually works" {
        $results = Get-DbaDbStoredProcedure -SqlInstance $script:instance2 -Database tempdb
        It "Should have standard properties" {
            $ExpectedProps = 'ComputerName,InstanceName,SqlInstance'.Split(',')
            ($results[0].PsObject.Properties.Name | Where-Object { $_ -in $ExpectedProps } | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }
        It "Should get test procedure: $procName" {
            ($results | Where-Object Name -eq $procName).Name | Should -Be $true
        }
        It "Should include system procedures" {
            ($results | Where-Object Name -eq 'sp_columns') | Should -Be $true
        }
    }

    Context "Exclusions work correctly" {
        It "Should contain no procs from master database" {
            $results = Get-DbaDbStoredProcedure -SqlInstance $script:instance2 -ExcludeDatabase master
            $results.Database | Should -Not -Contain 'master'
        }
        It "Should exclude system procedures" {
            $results = Get-DbaDbStoredProcedure -SqlInstance $script:instance2 -Database tempdb -ExcludeSystemSp
            $results | Where-Object Name -eq 'sp_helpdb' | Should -BeNullOrEmpty
        }
    }

    Context "Piping works" {
        It "Should allow piping from string" {
            $results = $script:instance2 | Get-DbaDbStoredProcedure -Database tempdb
            ($results | Where-Object Name -eq $procName).Name | Should -Not -BeNullOrEmpty
        }
        It "Should allow piping from Get-DbaDatabase" {
            $results = Get-DbaDatabase -SqlInstance $script:instance2 -Database tempdb | Get-DbaDbStoredProcedure
            ($results | Where-Object Name -eq $procName).Name | Should -Not -BeNullOrEmpty
        }
    }
}