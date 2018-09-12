$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

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