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
        [object[]]$params = (Get-ChildItem function:\Get-DbaAgReplica).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'AvailabilityGroup', 'Replica', 'EnableException'
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
        Context "gets ag replicas" {
            $results = Get-DbaAgReplica -SqlInstance sql2016c
            It "returns results with proper data" {
                $results.ConnectionState | Should -Be 'Unknown', 'Unknown', 'Disconnected'
                $results.EndPointUrl -contains 'TCP://sql2016c.base.local:5022'| Should -Be $true
            }
        }
    }
}