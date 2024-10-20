param($ModuleName = 'dbatools')

Describe "Get-DbatoolsLog" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbatoolsLog
        }

        It "has the required parameters" {
            $params = @(
                "FunctionName",
                "ModuleName",
                "Target",
                "Tag",
                "Last",
                "LastError",
                "Skip",
                "Runspace",
                "Level",
                "Raw",
                "Errors"
            )
            $params | ForEach-Object {
                It "has the required parameter: <_>" {
                    $CommandUnderTest | Should -HaveParameter $PSItem
                }
            }
        }
    }

    Context "Command usage" {
        BeforeAll {
            # Add any necessary setup for command usage tests
        }

        It "Should return log entries" {
            $result = Get-DbatoolsLog
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should filter by FunctionName" {
            $functionName = "Test-Function"
            $result = Get-DbatoolsLog -FunctionName $functionName
            $result | ForEach-Object { $_.FunctionName | Should -Be $functionName }
        }

        It "Should filter by ModuleName" {
            $moduleName = "dbatools"
            $result = Get-DbatoolsLog -ModuleName $moduleName
            $result | ForEach-Object { $_.ModuleName | Should -Be $moduleName }
        }

        It "Should limit results with Last parameter" {
            $last = 5
            $result = Get-DbatoolsLog -Last $last
            $result.Count | Should -Be $last
        }

        It "Should return raw results when Raw switch is used" {
            $result = Get-DbatoolsLog -Raw
            $result | Should -BeOfType [PSCustomObject]
        }

        It "Should return only errors when Errors switch is used" {
            $result = Get-DbatoolsLog -Errors
            $result | ForEach-Object { $_.Level | Should -Be 'Error' }
        }
    }
}
