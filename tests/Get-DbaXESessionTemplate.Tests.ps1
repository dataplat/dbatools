$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 4
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaXESessionTemplate).Parameters.Keys
        $knownParameters = 'Path', 'Pattern', 'Template', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Get Template Index" {
        $results = Get-DbaXESessionTemplate
        It "returns good results with no missing information" {
            $results | Where-Object Name -eq $null | Should Be $null
            $results | Where-Object TemplateName -eq $null | Should Be $null
            $results | Where-Object Description -eq $null | Should Be $null
            $results | Where-Object Category -eq $null | Should Be $null
        }
    }
}