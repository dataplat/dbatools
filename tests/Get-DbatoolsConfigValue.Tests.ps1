param($ModuleName = 'dbatools')

Describe "Get-DbatoolsConfigValue" {
    BeforeAll {
        $CommandName = $PSCommandPath.Split('\')[-1].Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbatoolsConfigValue
        }
        It "Should have FullName as a parameter" {
            $CommandUnderTest | Should -HaveParameter FullName
        }
        It "Should have Fallback as a parameter" {
            $CommandUnderTest | Should -HaveParameter Fallback
        }
        It "Should have NotNull as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter NotNull
        }
    }

    # Add more contexts and tests as needed for integration testing
    # For example:
    # Context "Command usage" {
    #     It "Should return a value when given a valid FullName" {
    #         $result = Get-DbatoolsConfigValue -FullName 'SomeValidConfigName'
    #         $result | Should -Not -BeNullOrEmpty
    #     }
    #     # Add more tests...
    # }
}
