param($ModuleName = 'dbatools')

Describe "Invoke-DbaPfRelog Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaPfRelog
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "Path",
                "Destination",
                "Type",
                "Append",
                "AllowClobber",
                "PerformanceCounter",
                "PerformanceCounterPath",
                "Interval",
                "BeginTime",
                "EndTime",
                "ConfigPath",
                "Summary",
                "InputObject",
                "Multithread",
                "AllTime",
                "Raw",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }
}

# Integration tests can be added below this line
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests for more guidance.
