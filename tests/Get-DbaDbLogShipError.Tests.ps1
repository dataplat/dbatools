$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-ChildItem function:\Get-DbaAgentJobStep).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Job', 'ExcludeJob', 'EnableException'
        It "Contains our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $knownParameters.Count
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Return values" {
        It "Get the log shipping errors" {
            $Results = @()
            $Results += Get-DbaDbLogShipError -SqlInstance $script:instance2
            $Results.Count | Should Be 0
        }
    }
}