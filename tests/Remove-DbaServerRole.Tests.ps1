<#
    The below statement stays in for every test you build.
#>
$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

<#
    Unit test is required for any command added
#>
Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'ServerRole', 'InputObject', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $instance = Connect-DbaInstance -SqlInstance $script:instance2
        $roleExecutor = "serverExecuter"
        $null = New-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor
    }
    AfterAll {
        $null = Remove-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor -Confirm:$false
    }
    Context "Command actually works" {
        It "It returns info about server-role removed" {
            $results = Remove-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor -Confirm:$false
            $results.ServerRole | Should Be $roleExecutor
        }

        It "Should not return server-role" {
            $results = Get-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor
            $results | Should Be $null
        }
    }
}