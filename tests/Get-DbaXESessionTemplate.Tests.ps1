$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'Path', 'Pattern', 'Template', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
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