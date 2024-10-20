param($ModuleName = 'dbatools')

Describe "Get-DbaWsfcCluster" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaWsfcCluster
        }

        It "has all the required parameters" {
            $params = @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    # Add more contexts and tests as needed for Get-DbaWsfcCluster
}
