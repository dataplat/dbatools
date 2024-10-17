param($ModuleName = 'dbatools')

Describe "Remove-DbaPfDataCollectorSet" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaPfDataCollectorSet
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have CollectorSet as a parameter" {
            $CommandUnderTest | Should -HaveParameter CollectorSet -Type String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Verifying command returns the proper results" {
        BeforeAll {
            $null = Get-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries' | Import-DbaPfDataCollectorSetTemplate
        }

        It "removes the data collector set" {
            $results = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Remove-DbaPfDataCollectorSet -Confirm:$false
            $results.Name | Should -Be 'Long Running Queries'
            $results.Status | Should -Be 'Removed'
        }

        It "returns a result" {
            $results = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries'
            $results.Name | Should -Be 'Long Running Queries'
        }

        It "returns no results" {
            $null = Remove-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' -Confirm:$false
            $results = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries'
            $results.Name | Should -BeNullOrEmpty
        }
    }
}
