param($ModuleName = 'dbatools')

Describe "Get-DbaUptime" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaUptime
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Credential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaUptime -SqlInstance $global:instance1
        }
        It "Should have correct properties" {
            $ExpectedProps = 'ComputerName', 'InstanceName', 'SqlServer', 'SqlUptime', 'WindowsUptime', 'SqlStartTime', 'WindowsBootTime', 'SinceSqlStart', 'SinceWindowsBoot'
            $results.PsObject.Properties.Name | Sort-Object | Should -Be ($ExpectedProps | Sort-Object)
        }
    }

    Context "Command can handle multiple SqlInstances" {
        BeforeAll {
            $results = Get-DbaUptime -SqlInstance $global:instance1, $global:instance2
        }
        It "Command resultset should contain 2 results" {
            $results.count | Should -Be 2
        }
        It "Windows up time should be more than SQL Uptime" {
            foreach ($result in $results) {
                $result.SqlUptime | Should -BeLessThan $result.WindowsUpTime
            }
        }
    }

    Context "Properties should return expected types" {
        BeforeAll {
            $results = Get-DbaUptime -SqlInstance $global:instance1
        }
        It "SqlStartTime should be a DbaDateTime" {
            $results.SqlStartTime | Should -BeOfType DbaDateTime
        }
        It "WindowsBootTime should be a DbaDateTime" {
            $results.WindowsBootTime | Should -BeOfType DbaDateTime
        }
    }
}
