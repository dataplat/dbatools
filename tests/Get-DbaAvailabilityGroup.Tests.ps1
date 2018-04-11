$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 5
        <#
            Get commands, Default count = 11
            Commands with SupportShouldProcess = 13
        #>
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaAvailabilityGroup).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'AvailabilityGroup', 'IsPrimary', 'EnableException'
        it "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }
        it "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    $dbname = "dbatoolsci_agroupdb"
    Context "gets ags" {
        $results = Get-DbaAvailabilityGroup -SqlInstance $script:instance3
        It "returns results with proper data" {
            $results.AvailabilityGroup | Should -Contain 'dbatoolsci_agroup'
            $results.AvailabilityDatabases.Name | Should -Contain $dbname
        }
        $results = Get-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup dbatoolsci_agroup
        It "returns a single result" {
            $results.AvailabilityGroup | Should -Be 'dbatoolsci_agroup'
            $results.AvailabilityDatabases.Name | Should -Be $dbname
        }
    }
} #$script:instance2 for appveyor