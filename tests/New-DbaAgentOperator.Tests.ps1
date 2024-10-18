param($ModuleName = 'dbatools')

Describe "New-DbaAgentOperator" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaAgentOperator
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Operator parameter" {
            $CommandUnderTest | Should -HaveParameter Operator -Type System.String
        }
        It "Should have EmailAddress parameter" {
            $CommandUnderTest | Should -HaveParameter EmailAddress -Type System.String
        }
        It "Should have NetSendAddress parameter" {
            $CommandUnderTest | Should -HaveParameter NetSendAddress -Type System.String
        }
        It "Should have PagerAddress parameter" {
            $CommandUnderTest | Should -HaveParameter PagerAddress -Type System.String
        }
        It "Should have PagerDay parameter" {
            $CommandUnderTest | Should -HaveParameter PagerDay -Type System.String
        }
        It "Should have SaturdayStartTime parameter" {
            $CommandUnderTest | Should -HaveParameter SaturdayStartTime -Type System.String
        }
        It "Should have SaturdayEndTime parameter" {
            $CommandUnderTest | Should -HaveParameter SaturdayEndTime -Type System.String
        }
        It "Should have SundayStartTime parameter" {
            $CommandUnderTest | Should -HaveParameter SundayStartTime -Type System.String
        }
        It "Should have SundayEndTime parameter" {
            $CommandUnderTest | Should -HaveParameter SundayEndTime -Type System.String
        }
        It "Should have WeekdayStartTime parameter" {
            $CommandUnderTest | Should -HaveParameter WeekdayStartTime -Type System.String
        }
        It "Should have WeekdayEndTime parameter" {
            $CommandUnderTest | Should -HaveParameter WeekdayEndTime -Type System.String
        }
        It "Should have IsFailsafeOperator parameter" {
            $CommandUnderTest | Should -HaveParameter IsFailsafeOperator -Type System.Management.Automation.SwitchParameter
        }
        It "Should have FailsafeNotificationMethod parameter" {
            $CommandUnderTest | Should -HaveParameter FailsafeNotificationMethod -Type System.String
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type System.Management.Automation.SwitchParameter
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Server[]
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
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
