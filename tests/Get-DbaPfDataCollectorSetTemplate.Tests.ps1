$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Verifying command returns all the required results" {
        It "returns not null values for required fields" {
            $results = Get-DbaPfDataCollectorSetTemplate
            foreach ($result in $results) {
                $result.Name | Should Not Be $null
                $result.Source | Should Not Be $null
                $result.Description | Should Not Be $null
            }
        }
        
        It "returns only one (and the proper) template" {
            $results = Get-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries'
            $results.Name | Should Be 'Long Running Queries'
        }
    }
}