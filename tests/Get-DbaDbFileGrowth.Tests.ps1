$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'InputObject', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Should return file information" {
        $result = Get-DbaDbFileGrowth -SqlInstance $script:instance2
        It "returns information about msdb files" {
            $result.Database -contains "msdb" | Should -Be $true
        }
    }

    Context "Should return file information for only msdb" {
        $result = Get-DbaDbFileGrowth -SqlInstance $script:instance2 -Database msdb | Select-Object -First 1
        It "returns only msdb files" {
            $result.Database | Should -Be "msdb"
        }
    }
}