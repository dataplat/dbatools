$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}
Describe "$commandname  Integration Test" -Tag "IntegrationTests" {
    $props = 'ComputerName', 'InstanceName', 'RecordSet', 'RowId', 'RecordSetId', 'Type', 'Name', 'Value', 'ValueType'
    $result = Get-DbaDbccMemoryStatus -SqlInstance $script:instance2

    Context "Validate standard output" {
        foreach ($prop in $props) {
            $p = $result[0].PSObject.Properties[$prop]
            It "Should return property: $prop" {
                $p.Name | Should Be $prop
            }
        }
    }

    Context "Command returns proper info" {
        It "returns results for DBCC MEMORYSTATUS" {
            $result.Count -gt 0 | Should Be $true
        }
    }
}