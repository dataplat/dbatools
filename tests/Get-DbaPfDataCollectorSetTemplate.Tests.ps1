$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'Path', 'Pattern', 'Template', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

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