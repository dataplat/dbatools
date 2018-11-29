$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Threshold', 'EnableException'
        $paramCount = $knownParameters.Count
        $SupportShouldProcess = $false
        if ($SupportShouldProcess) {
            $defaultParamCount = 13
        } else {
            $defaultParamCount = 11
        }
        $command = Get-Command -Name $CommandName
        [object[]]$params = $command.Parameters.Keys

        It "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }

        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Command returns proper info" {
        $results = Get-DbaLatchStatistic -SqlInstance $script:instance2 -Threshold 100

        It "returns results" {
            $results.Count -gt 0 | Should Be $true
        }

        foreach ($result in $results) {
            It "returns a hyperlink" {
                $result.URL -match 'sqlskills.com' | Should Be $true
            }
        }
    }
}