$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'Path', 'Pattern', 'Template', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
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