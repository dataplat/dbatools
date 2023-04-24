$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Alert', 'Category', 'DatabaseName', 'DelayBetweenResponses', 'Disabled', 'EventDescriptionKeyword', 'EventSource', 'JobId', 'MessageId', 'NotificationMessage', 'PerformanceCondition', 'Severity', 'WmiEventNamespace', 'WmiEventQuery', 'NotifyMethod', 'Operator', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    $parameters = @{
        SqlInstance           = "localhost"
        Alert                 = "Test Alert"
        DelayBetweenResponses = 60
        Disabled              = $false
        NotifyMethod          = "NotifyEmail"
        NotificationMessage   = "Test Notification"
        Severity              = 17
        EnableException       = $true
    }

    Context 'Creating a new SQL Server Agent alert' {
        It 'Should create a new alert' {
            $alert = New-DbaAgentAlert @parameters

            # Assert
            $alert.Name | Should -Be 'Test Alert'
            $alert.DelayBetweenResponses | Should -Be 60
            $alert.IsEnabled | Should -Be $true
            $alert.Severity | Should -Be 17

            Get-DbaAgentAlert -SqlInstance $script:instance2 -Alert $alertParams.Alert | Should Not Be $null
        }
    }
}
#$script:instance3