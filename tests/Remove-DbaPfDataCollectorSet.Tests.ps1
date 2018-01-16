$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $null = Get-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries' | Import-DbaPfDataCollectorSetTemplate
    }
    Context "Verifying command return the proper results" {
        It "removes the data collector set" {
            $results = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Remove-DbaPfDataCollectorSet
            $results.Name | Should Be 'Long Running Queries'
            $results.ComputerName | Should Be $env:COMPUTERNAME
        }
        
        It "returns no results" {
            $results = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries'
            $results.Name | Should Be $null
        }
        
        $null = Get-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries' | Import-DbaPfDataCollectorSetTemplate
        
        It "returns no results" {
            $results = Remove-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries'
            $results.Name | Should Be $null
        }
    }
}