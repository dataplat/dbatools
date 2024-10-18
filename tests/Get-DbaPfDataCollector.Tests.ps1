param($ModuleName = 'dbatools')

Describe "Get-DbaPfDataCollector" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPfDataCollector
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type System.Management.Automation.PSCredential
        }
        It "Should have CollectorSet as a parameter" {
            $CommandUnderTest | Should -HaveParameter CollectorSet -Type System.String[]
        }
        It "Should have Collector as a parameter" {
            $CommandUnderTest | Should -HaveParameter Collector -Type System.String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type System.Object[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Verifying command works" {
        It "returns a result with the right computername and name is not null" {
            $results = Get-DbaPfDataCollector | Select-Object -First 1
            $results.ComputerName | Should -Be $env:COMPUTERNAME
            $results.Name | Should -Not -BeNullOrEmpty
        }
    }
}
