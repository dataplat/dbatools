$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        $knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException'
        $SupportShouldProcess = $false
        $command = Get-Command -Name $CommandName
        [object[]]$params = $command.Parameters.Keys
        It "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $knownParameters.Count
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Components are properly retreived" {
        It "Should return the right values" {
            $results = Get-DbaCmsRegServerStore -SqlInstance $script:instance2
            $results.InstanceName | Should -Not -Be $null
            $results.DisplayName | Should -Be "Central Management Servers"
        }
    }
}