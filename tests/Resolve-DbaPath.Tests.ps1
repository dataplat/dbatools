param($ModuleName = 'dbatools')

Describe "Resolve-DbaPath Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Resolve-DbaPath
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "Path",
                "Provider",
                "SingleItem",
                "NewChild"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }
}
