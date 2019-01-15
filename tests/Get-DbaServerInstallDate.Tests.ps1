$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 5
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaServerInstallDate).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Credential', 'IncludeWindows', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    Context "Gets SQL Server Install Date" {
        $results = Get-DbaServerInstallDate -SqlInstance $script:instance2
        It "Gets results" {
            $results | Should Not Be $null
        }
    }
    Context "Gets SQL Server Install Date and Windows Install Date" {
        $results = Get-DbaServerInstallDate -SqlInstance $script:instance2 -IncludeWindows
        It "Gets results" {
            $results | Should Not Be $null
        }
    }
}