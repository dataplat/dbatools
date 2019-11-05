$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    Context "Gets UserOptions for the Instance" {
        $results = Get-DbaInstanceUserOption -SqlInstance $script:instance2 | Where-Object {$_.name -eq 'AnsiNullDefaultOff'}
        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should return AnsiNullDefaultOff UserOption" {
            $results.Name | Should Be 'AnsiNullDefaultOff'
        }
        It "Should be set to false" {
            $results.Value | Should Be $false
        }
    }
}