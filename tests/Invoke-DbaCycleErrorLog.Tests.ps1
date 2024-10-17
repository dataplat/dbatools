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

        It "Should have SqlInstance parameter" {
            $command | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }

        It "Should have SqlCredential parameter" {
            $command | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }

        It "Should have Type parameter" {
            $command | Should -HaveParameter Type -Type String -Not -Mandatory
        }

        It "Should have EnableException parameter" {
            $command | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }

        It "Should have common parameters" {
            $command | Should -HaveParameter Verbose -Type Switch -Not -Mandatory
            $command | Should -HaveParameter Debug -Type Switch -Not -Mandatory
            $command | Should -HaveParameter ErrorAction -Type ActionPreference -Not -Mandatory
            $command | Should -HaveParameter WarningAction -Type ActionPreference -Not -Mandatory
            $command | Should -HaveParameter InformationAction -Type ActionPreference -Not -Mandatory
            $command | Should -HaveParameter ErrorVariable -Type String -Not -Mandatory
            $command | Should -HaveParameter WarningVariable -Type String -Not -Mandatory
            $command | Should -HaveParameter InformationVariable -Type String -Not -Mandatory
            $command | Should -HaveParameter OutVariable -Type String -Not -Mandatory
            $command | Should -HaveParameter OutBuffer -Type Int32 -Not -Mandatory
            $command | Should -HaveParameter PipelineVariable -Type String -Not -Mandatory
            $command | Should -HaveParameter WhatIf -Type Switch -Not -Mandatory
            $command | Should -HaveParameter Confirm -Type Switch -Not -Mandatory
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
