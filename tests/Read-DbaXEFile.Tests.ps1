param($ModuleName = 'dbatools')

Describe "Read-DbaXEFile" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
        $base = (Get-Module -Name dbatools | Where-Object ModuleBase -notmatch net).ModuleBase
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Read-DbaXEFile
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type Object[] -Mandatory:$false
        }
        It "Should have Raw as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Raw -Type switch -Mandatory:$false
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch -Mandatory:$false
        }
    }

    Context "Verifying command output" {
        BeforeDiscovery {
            $env:skipIntegrationTests = [Environment]::GetEnvironmentVariable('DBA_TOOLS_SKIP_INTEGRATION_TESTS') -eq $true
        }

        It "returns some results using Raw parameter" -Skip:$skipIntegrationTests {
            $results = Get-DbaXESession -SqlInstance $global:instance2 | Read-DbaXEFile -Raw -WarningAction SilentlyContinue
            [System.Linq.Enumerable]::Count($results) | Should -BeGreaterThan 1
        }

        It "returns some results without Raw parameter" -Skip:$skipIntegrationTests {
            $results = Get-DbaXESession -SqlInstance $global:instance2 | Read-DbaXEFile -WarningAction SilentlyContinue
            $results.Count | Should -BeGreaterThan 1
        }
    }
}
