$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'OperatorName', 'EmailAddress', 'NetSendAddress', 'PagerAddress', 'PagerDay', 'SaturdayStartTime', 'SaturdayEndTime', 'SundayStartTime', 'SundayEndTime', 'WeekendStartTime', 'WeekendEndTime', 'IsFailsafeOperator', 'FailsafeNotificationMethod', 'Force', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "New Agent Operator is added properly" {

        It "Should have the right name" {
            $results = New-DbaAgentOperator -SqlInstance $script:instance2 -Operator DBA -OperatorEmail operator@operator.com -PagerDays Everyday
            $results.Name | Should Be "DBA"
        }

        # Cleanup and ignore all output
        #$null = Remove-DbaAgentOperator -SqlInstance $script:instance2 -Operator OperatorTest1
    }
}