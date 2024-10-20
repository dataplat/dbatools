param($ModuleName = 'dbatools')

Describe "Copy-DbaAgentJobCategory" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Copy-DbaAgentJobCategory
        }
        $paramList = @(
            'Source',
            'SourceSqlCredential',
            'Destination',
            'DestinationSqlCredential',
            'CategoryType',
            'JobCategory',
            'AgentCategory',
            'OperatorCategory',
            'Force',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have parameter: <_>" -ForEach $paramList {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Command copies jobs properly" -Tag "IntegrationTests" {
        BeforeAll {
            $null = New-DbaAgentJobCategory -SqlInstance $global:instance2 -Category 'dbatoolsci test category'
        }
        AfterAll {
            $null = Remove-DbaAgentJobCategory -SqlInstance $global:instance2 -Category 'dbatoolsci test category' -Confirm:$false
        }

        It "returns one success" {
            $results = Copy-DbaAgentJobCategory -Source $global:instance2 -Destination $global:instance3 -JobCategory 'dbatoolsci test category'
            $results.Name | Should -Be "dbatoolsci test category"
            $results.Status | Should -Be "Successful"
        }

        It "does not overwrite" {
            $results = Copy-DbaAgentJobCategory -Source $global:instance2 -Destination $global:instance3 -JobCategory 'dbatoolsci test category'
            $results.Name | Should -Be "dbatoolsci test category"
            $results.Status | Should -Be "Skipped"
        }
    }
}
