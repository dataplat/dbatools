param($ModuleName = 'dbatools')

Describe "Remove-DbaServerRole Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaServerRole
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "ServerRole",
            "InputObject",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

Describe "Remove-DbaServerRole Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    BeforeAll {
        $instance = Connect-DbaInstance -SqlInstance $global:instance2
        $roleExecutor = "serverExecuter"
        $null = New-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor
    }

    AfterAll {
        $null = Remove-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor -Confirm:$false
    }

    Context "Command actually works" {
        It "It returns info about server-role removed" {
            $results = Remove-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor -Confirm:$false
            $results.ServerRole | Should -Be $roleExecutor
        }

        It "Should not return server-role" {
            $results = Get-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor
            $results | Should -BeNullOrEmpty
        }
    }
}
