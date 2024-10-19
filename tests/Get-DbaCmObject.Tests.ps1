param($ModuleName = 'dbatools')

Describe "Get-DbaCmObject" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaCmObject
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "ClassName",
                "Query",
                "ComputerName",
                "Credential",
                "Namespace",
                "DoNotUse",
                "Force",
                "SilentlyContinue",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        It "returns a bias that's an int" {
            $result = Get-DbaCmObject -ClassName Win32_TimeZone
            $result.Bias | Should -BeOfType [int]
        }
    }
}
