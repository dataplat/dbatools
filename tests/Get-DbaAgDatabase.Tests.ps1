$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 5
        <#
            Get commands, Default count = 11
            Commands with SupportShouldProcess = 13
        #>
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaAgDatabase).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'AvailabilityGroup', 'Database', 'EnableException'
        it "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }
        it "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

InModuleScope dbatools {
    . "$PSScriptRoot\constants.ps1"
    Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
        Mock Connect-SqlInstance {
            Import-Clixml $script:appveyorlabrepo\agserver.xml
        }
        Context "gets ag databases" {
            $results = Get-DbaAgDatabase -SqlInstance sql2016c
            foreach ($result in $results) {
                It "returns results with proper data" {
                    $result.Replica | Should -Be 'SQL2016C'
                    $result.SynchronizationState | Should -Be 'NotSynchronizing'
                }
            }
            $results = Get-DbaAgDatabase -SqlInstance sql2016c -Database WSS_Content
            It "returns results with proper data for one database" {
                $results.Replica | Should -Be 'SQL2016C'
                $results.SynchronizationState | Should -Be 'NotSynchronizing'
                $results.DatabaseName | Should -Be 'WSS_Content'
            }
        }
    }
}