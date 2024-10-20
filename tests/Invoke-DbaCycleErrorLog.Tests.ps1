param($ModuleName = 'dbatools')

Describe "Invoke-DbaCycleErrorLog Unit Tests" -Tag "UnitTests" {
    BeforeAll {
        # Importing constants and any necessary setup
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandName = "Invoke-DbaCycleErrorLog"
            $command = Get-Command $CommandName
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Type",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $command | Should -HaveParameter $PSItem
        }
    }
}

Describe "Invoke-DbaCycleErrorLog Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        # Importing constants and any necessary setup
        . "$PSScriptRoot\constants.ps1"
        $results = Invoke-DbaCycleErrorLog -SqlInstance $global:instance1 -Type instance
    }

    Context "Validate output" {
        It "Should have correct properties" {
            $ExpectedProps = 'ComputerName', 'InstanceName', 'SqlInstance', 'LogType', 'IsSuccessful', 'Notes'
            $results.PSObject.Properties.Name | Should -Be $ExpectedProps
        }

        It "Should cycle instance error log" {
            $results.LogType | Should -Be "instance"
        }
    }
}
