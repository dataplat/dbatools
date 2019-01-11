$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 5
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaRgResourcePool).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Type', 'InputObject', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {
        $results = Get-DbaRgResourcePool -SqlInstance $script:Instance2
        it "Gets Results" {
            $results | Should Not Be $null
        }
    }
    Context "Command actually works using -Type" {
        $results = Get-DbaRgResourcePool -SqlInstance $script:Instance2 -Type Internal
        it "Gets Results" {
            $results | Should Not Be $null
        }
    }
}