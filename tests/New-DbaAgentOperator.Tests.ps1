$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Operator', 'EmailAddress', 'NetSendAddress', 'PagerAddress', 'PagerDay', 'SaturdayStartTime', 'SaturdayEndTime', 'SundayStartTime', 'SundayEndTime', 'WeekdayStartTime', 'WeekdayEndTime', 'IsFailsafeOperator', 'FailsafeNotificationMethod', 'Force', 'ServerObject', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $instance2 = Connect-DbaInstance -SqlInstance $script:instance2
        $email1 = "test1$($random)@test.com"
        $email2 = "test2$($random)@test.com"
        $email3 = "test3$($random)@test.com"
        $email4 = "test4$($random)@test.com"
    }

    AfterAll {
        $null = Remove-DbaAgentOperator -SqlInstance $instance2 -Operator $email1 -Confirm:$false
        $null = Remove-DbaAgentOperator -SqlInstance $instance2 -Operator $email2 -Confirm:$false
        $null = Remove-DbaAgentOperator -SqlInstance $instance2 -Operator $email3 -Confirm:$false
        $null = Remove-DbaAgentOperator -SqlInstance $instance2 -Operator $email4 -Confirm:$false
    }

    Context "New Agent Operator is added properly" {

        It "Should have the right name" {
            $results = New-DbaAgentOperator -SqlInstance $instance2 -Operator $email1 -EmailAddress $email1 -PagerDay Everyday -Force
            $results.Name | Should Be $email1
        }

        It "Create an agent operator with only the defaults" {
            $results = New-DbaAgentOperator -SqlInstance $instance2 -Operator $email2 -EmailAddress $email2
            $results.Name | Should Be $email2
        }

        It "Pipeline command" {
            $results = $instance2 | New-DbaAgentOperator -Operator $email3 -EmailAddress $email3
            $results.Name | Should Be $email3
        }

        It "Creates an agent operator with all params" {
            $results = New-DbaAgentOperator -SqlInstance $instance2 -Operator $email4 -EmailAddress $email4 -NetSendAddress dbauser1 -PagerAddress dbauser1@pager.dbatools.io -PagerDay Everyday -SaturdayStartTime 070000 -SaturdayEndTime 180000 -SundayStartTime 080000 -SundayEndTime 170000 -WeekdayStartTime 060000 -WeekdayEndTime 190000
            $results.Enabled | Should -Be $true
            $results.Name | Should Be $email4
            $results.EmailAddress | Should -Be $email4
            $results.NetSendAddress | Should -Be dbauser1
            $results.PagerAddress | Should -Be dbauser1@pager.dbatools.io
            $results.PagerDays | Should -Be Everyday
            $results.SaturdayPagerStartTime.ToString() | Should -Be "07:00:00"
            $results.SaturdayPagerEndTime.ToString() | Should -Be "18:00:00"
            $results.SundayPagerStartTime.ToString() | Should -Be "08:00:00"
            $results.SundayPagerEndTime.ToString() | Should -Be "17:00:00"
            $results.WeekdayPagerStartTime.ToString() | Should -Be "06:00:00"
            $results.WeekdayPagerEndTime.ToString() | Should -Be "19:00:00"
        }
    }
}