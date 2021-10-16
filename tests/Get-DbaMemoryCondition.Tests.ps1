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

Describe "Get-DbaMemoryCondition Integration Test" -Tag "IntegrationTests" {
    Context "Command actually works" {
        $results = Get-DbaMemoryCondition -SqlInstance $script:instance1

        It "returns results" {
            $($results | Measure-Object).Count -gt 0 | Should Be $true
        }
        It "has the correct properties" {
            $result = $results[0]
            $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Runtime,NotificationTime,NotificationType,MemoryUtilizationPercent,TotalPhysicalMemory,AvailablePhysicalMemory,TotalPageFile,AvailablePageFile,TotalVirtualAddressSpace,AvailableVirtualAddressSpace,NodeId,SQLReservedMemory,SQLCommittedMemory,RecordId,Type,Indicators,RecordTime,CurrentTime'.Split(',')
            ($result.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }
    }
}