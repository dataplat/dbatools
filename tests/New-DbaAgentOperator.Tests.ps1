param($ModuleName = 'dbatools')

Describe "New-DbaAgentOperator" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaAgentOperator
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Operator",
            "EmailAddress",
            "NetSendAddress",
            "PagerAddress",
            "PagerDay",
            "SaturdayStartTime",
            "SaturdayEndTime",
            "SundayStartTime",
            "SundayEndTime",
            "WeekdayStartTime",
            "WeekdayEndTime",
            "IsFailsafeOperator",
            "FailsafeNotificationMethod",
            "Force",
            "InputObject",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "New Agent Operator is added properly" {
        BeforeAll {
            $random = Get-Random
            $server2 = Connect-DbaInstance -SqlInstance $global:instance2
            $email1 = "test1$($random)@test.com"
            $email2 = "test2$($random)@test.com"
            $email3 = "test3$($random)@test.com"
            $email4 = "test4$($random)@test.com"
        }

        AfterAll {
            $null = Remove-DbaAgentOperator -SqlInstance $server2 -Operator $email1 -Confirm:$false
            $null = Remove-DbaAgentOperator -SqlInstance $server2 -Operator $email2 -Confirm:$false
            $null = Remove-DbaAgentOperator -SqlInstance $server2 -Operator $email3 -Confirm:$false
            $null = Remove-DbaAgentOperator -SqlInstance $server2 -Operator $email4 -Confirm:$false
        }

        It "Should have the right name" {
            $results = New-DbaAgentOperator -SqlInstance $server2 -Operator $email1 -EmailAddress $email1 -PagerDay Everyday -Force
            $results.Name | Should -Be $email1
        }

        It "Create an agent operator with only the defaults" {
            $results = New-DbaAgentOperator -SqlInstance $server2 -Operator $email2 -EmailAddress $email2
            $results.Name | Should -Be $email2
        }

        It "Pipeline command" {
            $results = $server2 | New-DbaAgentOperator -Operator $email3 -EmailAddress $email3
            $results.Name | Should -Be $email3
        }

        It "Creates an agent operator with all params" {
            $results = New-DbaAgentOperator -SqlInstance $server2 -Operator $email4 -EmailAddress $email4 -NetSendAddress dbauser1 -PagerAddress dbauser1@pager.dbatools.io -PagerDay Everyday -SaturdayStartTime 070000 -SaturdayEndTime 180000 -SundayStartTime 080000 -SundayEndTime 170000 -WeekdayStartTime 060000 -WeekdayEndTime 190000
            $results.Enabled | Should -Be $true
            $results.Name | Should -Be $email4
            $results.EmailAddress | Should -Be $email4
            $results.NetSendAddress | Should -Be 'dbauser1'
            $results.PagerAddress | Should -Be 'dbauser1@pager.dbatools.io'
            $results.PagerDays | Should -Be 'Everyday'
            $results.SaturdayPagerStartTime.ToString() | Should -Be "07:00:00"
            $results.SaturdayPagerEndTime.ToString() | Should -Be "18:00:00"
            $results.SundayPagerStartTime.ToString() | Should -Be "08:00:00"
            $results.SundayPagerEndTime.ToString() | Should -Be "17:00:00"
            $results.WeekdayPagerStartTime.ToString() | Should -Be "06:00:00"
            $results.WeekdayPagerEndTime.ToString() | Should -Be "19:00:00"
        }
    }
}
