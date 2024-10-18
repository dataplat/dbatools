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
            $command | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }

        It "Should have SqlCredential parameter" {
            $command | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }

        It "Should have Type parameter" {
            $command | Should -HaveParameter Type -Type System.String -Mandatory:$false
        }

        It "Should have EnableException parameter" {
            $command | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
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
