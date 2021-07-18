$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Context "Validate parameters" {
    [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
    [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'InputObject', 'EnableException'

    It "Should only contain our specific parameters" {
        Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Should return file information" {
        $results = Get-DbaDbFileMapping -SqlInstance $script:instance1
        It "returns information about multiple databases" {
            $results.Database -contains "tempdb" | Should -Be $true
            $results.Database -contains "master" | Should -Be $true
        }
    }
    Context "Should return file information for a single database" {
        $results = Get-DbaDbFileMapping -SqlInstance $script:instance1 -Database tempdb
        It "returns information about tempdb" {
            $results.Database -contains "tempdb" | Should -Be $true
            $results.Database -contains "master" | Should -Be $false
        }
    }
}