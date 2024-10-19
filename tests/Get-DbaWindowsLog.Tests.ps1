param($ModuleName = 'dbatools')

Describe "Get-DbaWindowsLog" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaWindowsLog
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "Start",
                "End",
                "Credential",
                "MaxThreads",
                "MaxRemoteThreads",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command returns proper info" {
        BeforeAll {
            $results = Get-DbaWindowsLog -SqlInstance $global:instance2
        }
        It "returns results" {
            $results.Count | Should -BeGreaterThan 0
        }
    }
}
