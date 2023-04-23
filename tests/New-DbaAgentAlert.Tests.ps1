$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Alert', 'CategoryName', 'DatabaseName', 'DelayBetweenResponses', 'Disabled', 'EventDescriptionKeyword', 'EventSource', 'IncludeEventDescription', 'JobId', 'MessageId', 'NotificationMessage', 'PerformanceCondition', 'Severity', 'WmiEventNamespace', 'EnableException'

        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    $parameters = @{
        SqlInstance             = 'localhost'
        Alert                   = 'Test Alert'
        CategoryName            = 'Test Category'
        DatabaseName            = 'TestDB'
        DelayBetweenResponses   = 60
        Disabled                = $false
        EventDescriptionKeyword = 'Test Keyword'
        EventSource             = 'Test Source'
        IncludeEventDescription = 'NotifyEmail'
        MessageId               = 1
        NotificationMessage     = 'Test Notification'
        PerformanceCondition    = 'Test Condition'
        Severity                = 'Critical'
        WmiEventNamespace       = 'Test Namespace'
        EnableException         = $true
    }

    Context 'Creating a new SQL Server Agent alert on instance2' {
        It 'Should create a new alert' {
            $alert = New-DbaAgentAlert @parameters

            # Assert
            $alert.Name | Should -Be 'Test Alert'
            $alert.CategoryName | Should -Be 'Test Category'
            $alert.DatabaseName | Should -Be 'TestDB'
            $alert.DelayBetweenResponses | Should -Be 60
            $alert.IsEnabled | Should -Be $true
            $alert.EventDescriptionKeyword | Should -Be 'Test Keyword'
            $alert.EventSource | Should -Be 'Test Source'
            $alert.IncludeEventDescription | Should -Be $true
            $alert.JobId | Should -Be 'Test Job'
            $alert.MessageId | Should -Be 1
            $alert.NotificationMessage | Should -Be 'Test Notification'
            $alert.PerformanceCondition | Should -Be 'Test Condition'
            $alert.Severity | Should -Be 'Critical'
            $alert.WmiEventNamespace | Should -Be 'Test Namespace'

            Get-DbaAgentAlert -SqlInstance $script:instance2 -Alert $alertParams.Alert | Should Not Be $null
        }
    }

    Context 'Creating a new SQL Server Agent alert on instance3' {
        It 'Should create a new alert' {
            $alertParams.SqlInstance = $script:instance3

            New-DbaAgentAlert @alertParams | Should Not Be $null

            Get-DbaAgentAlert -SqlInstance $script:instance3 -Alert $alertParams.Alert | Should Not Be $null
        }
    }
}