$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaProductKey).Parameters.Keys
        $knownParameters = 'ComputerName', 'SqlCredential', 'Credential', 'EnableException'
        $paramCount = $knownParameters.Count
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    Context "Gets ProductKey for Instances on $($env:ComputerName)" {
        $results = Get-DbaProductKey -ComputerName $env:ComputerName
        It "Gets results" {
            $results | Should Not Be $null
        }
        Foreach ($row in $results) {
            It "Should have Version $($row.Version)" {
                $row.Version | Should not be $null
            }
            It "Should have Edition $($row.Edition)" {
                $row.Edition | Should not be $null
            }
            It "Should have Key $($row.key)" {
                $row.key | Should not be $null
            }
        }
    }
}