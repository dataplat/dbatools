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
            Import-CliXml $script:appveyorlabrepo\agserver.xml
        }
        Context "gets ag databases" {
            $results = Get-DbaAgListener -SqlInstance sql2016c
            foreach ($result in $results) {
                It "returns results with the right listener information" {
                    $result.Name | Should -Be 'splistener'
                    $result.PortNumber | Should -Be '20200'
                }
            }
            $results = Get-DbaAgListener -SqlInstance sql2016c -Listener splistener
            foreach ($result in $results) {
                It "returns results with the right listener information for a single listener" {
                    $result.Name | Should -Be 'splistener'
                    $result.PortNumber | Should -Be '20200'
                }
            }
            $results = Get-DbaAgListener -SqlInstance sql2016c -Listener doesntexist
            It "does not return a non existent listener" {
            $results | Should -Be $null
            }
        }
    }
}