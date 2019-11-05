$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Event', 'Filter', 'DelaySeconds', 'StopOnError', 'ReplayIntervalSeconds', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Creates a smart object" {
        It "returns the object with all of the correct properties" {
            $columns = "cpu_time", "duration", "physical_reads", "logical_reads", "writes", "row_count", "batch_text"
            $results = New-DbaXESmartTableWriter -SqlInstance $script:instance2 -Database dbadb -Table deadlocktracker -OutputColumn $columns -Filter "duration > 10000"
            $results.ServerName | Should -Be $script:instance2
            $results.DatabaseName | Should -be 'dbadb'
            $results.Password | Should -Be $null
            $results.TableName | Should -Be 'deadlocktracker'
            $results.IsSingleEvent | Should -Be $true
            $results.FailOnSingleEventViolation | Should -Be $false
        }
    }
}