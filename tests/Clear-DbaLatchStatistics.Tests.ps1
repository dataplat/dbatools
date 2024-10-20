param($ModuleName = 'dbatools')

Describe "Clear-DbaLatchStatistics Unit Tests" -Tag "UnitTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Clear-DbaLatchStatistics
        }
        $knownParameters = @(
            'SqlInstance',
            'SqlCredential',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have the correct parameters" {
            $command | Should -HaveParameter $knownParameters
        }
    }
}

Describe "Clear-DbaLatchStatistics Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Command executes properly and returns proper info" {
        BeforeAll {
            $results = Clear-DbaLatchStatistics -SqlInstance $global:instance1 -Confirm:$false
        }

        It "returns success" {
            $results.Status | Should -Be 'Success'
        }
    }
}
