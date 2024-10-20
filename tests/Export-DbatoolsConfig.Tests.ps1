param($ModuleName = 'dbatools')

Describe "Export-DbatoolsConfig" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbatoolsConfig
        }
        It "has all the required parameters" {
            $params = @(
                "FullName",
                "Module",
                "Name",
                "Config",
                "ModuleName",
                "ModuleVersion",
                "Scope",
                "OutPath",
                "SkipUnchanged",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }
}

# Integration tests can be added here
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests for more guidance
