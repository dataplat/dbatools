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
            $command | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }

        It "Should have SqlCredential parameter" {
            $command | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }

        It "Should have Type parameter" {
            $command | Should -HaveParameter Type -Type String -Mandatory:$false
        }

        It "Should have EnableException parameter" {
            $command | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }

        It "Should have common parameters" {
            $command | Should -HaveParameter Verbose -Type Switch -Mandatory:$false
            $command | Should -HaveParameter Debug -Type Switch -Mandatory:$false
            $command | Should -HaveParameter ErrorAction -Type ActionPreference -Mandatory:$false
            $command | Should -HaveParameter WarningAction -Type ActionPreference -Mandatory:$false
            $command | Should -HaveParameter InformationAction -Type ActionPreference -Mandatory:$false
            $command | Should -HaveParameter ErrorVariable -Type String -Mandatory:$false
            $command | Should -HaveParameter WarningVariable -Type String -Mandatory:$false
            $command | Should -HaveParameter InformationVariable -Type String -Mandatory:$false
            $command | Should -HaveParameter OutVariable -Type String -Mandatory:$false
            $command | Should -HaveParameter OutBuffer -Type Int32 -Mandatory:$false
            $command | Should -HaveParameter PipelineVariable -Type String -Mandatory:$false
            $command | Should -HaveParameter WhatIf -Type Switch -Mandatory:$false
            $command | Should -HaveParameter Confirm -Type Switch -Mandatory:$false
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
