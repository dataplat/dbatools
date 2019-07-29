$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Job', 'Schedule', 'ScheduleId', 'Disabled', 'Description', 'StartStepId', 'Category', 'OwnerLogin', 'EventLogLevel', 'EmailLevel', 'PageLevel', 'EmailOperator', 'NetsendOperator', 'PageOperator', 'DeleteLevel', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "New Agent JOb is added properly" {

        It "Should have the right name and description" {
            $results = New-DbaAgentJob -SqlInstance $script:instance2 -Job "Job One" -Description "Just another job"
            $results.Name | Should Be "Job One"
            $results.Description | Should Be "Just another job"
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentJob -SqlInstance $script:instance2 -Job "Job One"
            $newresults.Name | Should Be "Job One"
            $newresults.Description | Should Be "Just another job"
        }

        It "Should not write over existing jobs" {
            $results = New-DbaAgentJob -SqlInstance $script:instance2 -Job "Job One" -Description "Just another job" -WarningAction SilentlyContinue -WarningVariable warn
            $warn -match "already exists" | Should Be $true
        }

        # Cleanup and ignore all output
        Remove-DbaAgentJob -SqlInstance $script:instance2 -Job "Job One" *> $null
    }
}