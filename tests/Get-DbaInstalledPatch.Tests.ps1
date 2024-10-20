param($ModuleName = 'dbatools')

Describe "Get-DbaInstalledPatch" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaInstalledPatch
        }

        $params = @(
            "ComputerName",
            "Credential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        It "Returns output when run against a valid instance" {
            $result = Get-DbaInstalledPatch -ComputerName $global:instance1
            $result | Should -Not -BeNullOrEmpty
        }
    }
}
