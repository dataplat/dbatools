$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        $knownParameters = 'SqlInstance', 'SqlCredential', 'CollectionMinutes', 'EnableException'
        $SupportShouldProcess = $false
        $command = Get-Command -Name $CommandName
        [object[]]$params = $command.Parameters.Keys
        It "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $knownParameters.Count
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Command returns proper info" {
        $results = Get-DbaCpuRingBuffer -SqlInstance $script:instance2 -CollectionMinutes 100

        It "returns results" {
            $results.Count -gt 0 | Should Be $true
        }
    }
}