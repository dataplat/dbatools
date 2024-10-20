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
            $params = @(
                "SqlInstance",
                "Start",
                "End",
                "Credential",
                "MaxThreads",
                "MaxRemoteThreads",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
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
