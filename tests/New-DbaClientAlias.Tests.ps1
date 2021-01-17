$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'ComputerName', 'Credential', 'ServerName', 'Alias', 'Protocol', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "adds the alias" {
        $results = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias-new -Verbose:$false
        It "returns accurate information" {
            $results.AliasName | Should Be dbatoolscialias-new, dbatoolscialias-new
        }
        $results | Remove-DbaClientAlias
    }
}