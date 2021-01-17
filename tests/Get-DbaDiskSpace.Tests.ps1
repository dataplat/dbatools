$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'ComputerName', 'Credential', 'Unit', 'SqlCredential', 'ExcludeDrive', 'CheckFragmentation', 'Force', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Disks are properly retrieved" {
        $results = Get-DbaDiskSpace -ComputerName $env:COMPUTERNAME
        It "returns at least the system drive" {
            $results.Name -contains "$env:SystemDrive\" | Should Be $true
        }

        $results = Get-DbaDiskSpace -ComputerName $env:COMPUTERNAME | Where-Object Name -eq "$env:SystemDrive\"
        It "has some valid properties" {
            $results.BlockSize -gt 0 | Should Be $true
            $results.SizeInGB -gt 0 | Should Be $true
        }
    }
}