$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Operator', 'Name', 'EmailAddress', 'NetSendAddress', 'PagerAddress', 'PagerDay', 'SaturdayStartTime', 'SaturdayEndTime', 'SundayStartTime', 'SundayEndTime', 'WeekdayStartTime', 'WeekdayEndTime', 'IsFailsafeOperator', 'FailsafeNotificationMethod', 'InputObject', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $instance2 = Connect-DbaInstance -SqlInstance $script:instance2 -Database msdb
        $instance2.Invoke("EXEC msdb.dbo.sp_add_operator @name=N'dbatools dba', @enabled=1, @pager_days=0")
    }

    AfterAll {
        $null = Remove-DbaAgentOperator -SqlInstance $instance2 -Operator 'dbatools dba' -Confirm:$false
    }

    Context "Set works" {
        It "Should change the name and email" {
            $results = Get-DbaAgentOperator -SqlInstance $instance2 -Operator 'dbatools dba' | Set-DbaAgentOperator -Name new -EmailAddress new@new.com
            $results = Get-DbaAgentOperator -SqlInstance $instance2 -Operator new
            $results.Count | Should -Be 1
            $results.EmailAddress | Should -Be "new@new.com"
        }
    }
}