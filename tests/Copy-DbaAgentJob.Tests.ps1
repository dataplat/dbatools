param($ModuleName = 'dbatools')

Describe "Copy-DbaAgentJob" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Copy-DbaAgentJob
        }
        $paramList = @(
            'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential',
            'Job', 'ExcludeJob', 'DisableOnSource', 'DisableOnDestination',
            'Force', 'InputObject', 'EnableException'
        )
        It "Should have parameter: <_>" -ForEach $paramList {
            $command | Should -HaveParameter $_ -Because "this parameter is required"
        }
        It "Should have WhatIf and Confirm switch parameters" {
            $command | Should -HaveParameter WhatIf -Mandatory:$false -Type switch
            $command | Should -HaveParameter Confirm -Mandatory:$false -Type switch
        }
    }

    Context "Command copies jobs properly" -Tag "IntegrationTests" {
        BeforeAll {
            $null = New-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_copyjob
            $null = New-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_copyjob_disabled
            $sourcejobs = Get-DbaAgentJob -SqlInstance $global:instance2
            $destjobs = Get-DbaAgentJob -SqlInstance $global:instance3
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_copyjob, dbatoolsci_copyjob_disabled -Confirm:$false
            $null = Remove-DbaAgentJob -SqlInstance $global:instance3 -Job dbatoolsci_copyjob, dbatoolsci_copyjob_disabled -Confirm:$false
        }

        It "returns one success" {
            $results = Copy-DbaAgentJob -Source $global:instance2 -Destination $global:instance3 -Job dbatoolsci_copyjob
            $results.Name | Should -Be "dbatoolsci_copyjob"
            $results.Status | Should -Be "Successful"
        }

        It "did not copy dbatoolsci_copyjob_disabled" {
            Get-DbaAgentJob -SqlInstance $global:instance3 -Job dbatoolsci_copyjob_disabled | Should -BeNullOrEmpty
        }

        It "disables jobs when requested" {
            (Get-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_copyjob_disabled).Enabled | Should -BeTrue
            $results = Copy-DbaAgentJob -Source $global:instance2 -Destination $global:instance3 -Job dbatoolsci_copyjob_disabled -DisableOnSource -DisableOnDestination -Force
            $results.Name | Should -Be "dbatoolsci_copyjob_disabled"
            $results.Status | Should -Be "Successful"
            (Get-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_copyjob_disabled).Enabled | Should -BeFalse
            (Get-DbaAgentJob -SqlInstance $global:instance3 -Job dbatoolsci_copyjob_disabled).Enabled | Should -BeFalse
        }
    }
}
