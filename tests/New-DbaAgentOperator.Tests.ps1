$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'OperatorName', 'EmailAddress', 'NetSendAddress', 'PagerAddress', 'PagerDays', 'SaturdayStartTime', 'SaturdayEndTime', 'SundayStartTime', 'SundayEndTime', 'WeekendStartTime', 'WeekendEndTime', 'IsFailsafeOperator', 'FailsafeNotificationMethod', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "New Agent Operator is added properly" {

        It "Should have the right name" {
            $results = New-DbaAgentOperator -SqlInstance -SqlInstance $script:instance2 -Operator DBA -OperatorEmail operator@operator.com -PagerDays Everyday
            $results.Name | Should Be "DBA"
        }

        # Cleanup and ignore all output
        #$null = Remove-DbaAgentOperator -SqlInstance $script:instance2 -Operator OperatorTest1
    }
}