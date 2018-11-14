$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "$PSScriptRoot\..\internal\functions\Connect-SqlInstance.ps1"

Describe "$commandname Unit Tests" -Tag 'UnitTests' {

    InModuleScope dbatools {

        Context "Parameter Validation" {

            [object[]]$params = (Get-ChildItem function:\Test-DbaRepLatency).Parameters.Keys
            $knownParameters = 'SqlInstance', 'Database', 'SqlCredential', 'PublicationName', 'TimeToLive', 'RetainToken', 'DisplayTokenHistory', 'EnableException'
            $paramCount = $knownParameters.Count
            $defaultParamCount = $params.Count - $paramCount

            It "Should contain our specific parameters" {
                ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
            }

            It "Should only contain $paramCount parameters" {
                $params.Count - $defaultParamCount | Should Be $paramCount
            }

        }
    }
}