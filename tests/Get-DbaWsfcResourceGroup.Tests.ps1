param($ModuleName = 'dbatools')

Describe "Get-DbaWsfcResourceGroup" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaWsfcResourceGroup
        }

        $params = @(
            "ComputerName",
            "Credential",
            "Name",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}
