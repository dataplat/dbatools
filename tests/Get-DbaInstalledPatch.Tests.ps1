param($ModuleName = 'dbatools')

Describe "Get-DbaInstalledPatch" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaInstalledPatch
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        It "Returns output when run against a valid instance" {
            $result = Get-DbaInstalledPatch -ComputerName $global:instance1
            $result | Should -Not -BeNullOrEmpty
        }
    }
}
