param($ModuleName = 'dbatools')

Describe "Get-DbaPfDataCollectorCounter" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPfDataCollectorCounter
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have CollectorSet as a parameter" {
            $CommandUnderTest | Should -HaveParameter CollectorSet
        }
        It "Should have Collector as a parameter" {
            $CommandUnderTest | Should -HaveParameter Collector
        }
        It "Should have Counter as a parameter" {
            $CommandUnderTest | Should -HaveParameter Counter
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Verifying command works" {
        It "returns a result with the right computername and name is not null" {
            $results = Get-DbaPfDataCollectorCounter | Select-Object -First 1
            $results.ComputerName | Should -Be $env:COMPUTERNAME
            $results.Name | Should -Not -BeNullOrEmpty
        }
    }
}
