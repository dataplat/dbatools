$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'InputObject', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $null = Get-DbaDatabase -SqlInstance $script:instance1
        $null = Connect-DbaInstance -SqlInstance $env:COMPUTERNAME -SqlConnectionOnly
    }
    Context "disconnets a server" {
        It "disconnects and returns some results" {
            $results = Get-DbaConnectedInstance | Disconnect-DbaInstance
            $results.Count | Should -BeGreaterThan 1
        }
    }
}