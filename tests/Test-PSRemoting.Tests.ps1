$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "$PSScriptRoot\..\private\functions\Test-PSRemoting.ps1"


Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'ComputerName', 'Credential', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "returns a boolean with no exceptions" {
        $result = Test-PSRemoting -ComputerName "funny"
        It "returns $false when failing" {
            $result | Should Be $false
        }
        $result = Test-PSRemoting -ComputerName localhost
        It "returns $true when succeeding" {
            $result | Should Be $true
        }
    }
    Context "handles an instance, using just the computername" {
        $result = Test-PSRemoting -ComputerName $script:instance1
        It "returns $true when succeeding" {
            $result | Should Be $true
        }
    }
}