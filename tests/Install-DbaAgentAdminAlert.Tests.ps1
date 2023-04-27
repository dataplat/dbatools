$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Category', 'Database', 'Operator', 'OperatorEmail', 'DelayBetweenResponses', 'Disabled', 'EventDescriptionKeyword', 'EventSource', 'JobId', 'ExcludeSeverity', 'ExcludeMessageId', 'NotificationMessage', 'NotifyMethod', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context 'Creating a new SQL Server Agent alert' {
        $parms = @{
            SqlInstance           = $script:instance2
            DelayBetweenResponses = 60
            Disabled              = $false
            NotifyMethod          = "NotifyEmail"
            NotificationMessage   = "Test Notification"
            Operator              = "Test Operator"
            OperatorEmail         = "dba@ad.local"
            ExcludeSeverity       = 0
            EnableException       = $true
        }

        It 'Should create a bunch of new alerts' {
            $alert = Install-DbaAgentAdminAlert @parms | Select-Object -First 1

            # Assert
            $alert.Name | Should -Not -BeNullOrEmpty
            $alert.DelayBetweenResponses | Should -Be 60
            $alert.IsEnabled | Should -Be $true
        }

        $parms.SqlInstance = $script:instance3
        $parms.ExcludeSeverity = 17

        It 'Should create a bunch of new alerts' {
            $alerts = Install-DbaAgentAdminAlert @parms

            # Assert
            $alerts.Severity | Should -No -Contain 17

            Get-DbaAgentAlert -SqlInstance $script:instance3 | Should -Not -BeNullOrEmpty
        }
    }
}