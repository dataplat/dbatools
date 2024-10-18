param($ModuleName = 'dbatools')

Describe "Set-DbaAgentOperator" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaAgentOperator
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Operator as a parameter" {
            $CommandUnderTest | Should -HaveParameter Operator -Type System.String[]
        }
        It "Should have Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type System.String
        }
        It "Should have EmailAddress as a parameter" {
            $CommandUnderTest | Should -HaveParameter EmailAddress -Type System.String
        }
        It "Should have NetSendAddress as a parameter" {
            $CommandUnderTest | Should -HaveParameter NetSendAddress -Type System.String
        }
        It "Should have PagerAddress as a parameter" {
            $CommandUnderTest | Should -HaveParameter PagerAddress -Type System.String
        }
        It "Should have PagerDay as a parameter" {
            $CommandUnderTest | Should -HaveParameter PagerDay -Type System.String
        }
        It "Should have SaturdayStartTime as a parameter" {
            $CommandUnderTest | Should -HaveParameter SaturdayStartTime -Type System.String
        }
        It "Should have SaturdayEndTime as a parameter" {
            $CommandUnderTest | Should -HaveParameter SaturdayEndTime -Type System.String
        }
        It "Should have SundayStartTime as a parameter" {
            $CommandUnderTest | Should -HaveParameter SundayStartTime -Type System.String
        }
        It "Should have SundayEndTime as a parameter" {
            $CommandUnderTest | Should -HaveParameter SundayEndTime -Type System.String
        }
        It "Should have WeekdayStartTime as a parameter" {
            $CommandUnderTest | Should -HaveParameter WeekdayStartTime -Type System.String
        }
        It "Should have WeekdayEndTime as a parameter" {
            $CommandUnderTest | Should -HaveParameter WeekdayEndTime -Type System.String
        }
        It "Should have IsFailsafeOperator as a parameter" {
            $CommandUnderTest | Should -HaveParameter IsFailsafeOperator -Type System.Management.Automation.Switch
        }
        It "Should have FailsafeNotificationMethod as a parameter" {
            $CommandUnderTest | Should -HaveParameter FailsafeNotificationMethod -Type System.String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Agent.Operator[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.Switch
        }
    }

    Context "Command usage" {
        BeforeAll {
            $instance2 = Connect-DbaInstance -SqlInstance $global:instance2 -Database msdb
            $instance2.Invoke("EXEC msdb.dbo.sp_add_operator @name=N'dbatools dba', @enabled=1, @pager_days=0")
        }

        AfterAll {
            $null = Remove-DbaAgentOperator -SqlInstance $instance2 -Operator 'dbatools dba' -Confirm:$false
        }

        It "Should change the name and email" {
            $results = Get-DbaAgentOperator -SqlInstance $instance2 -Operator 'dbatools dba' | Set-DbaAgentOperator -Name new -EmailAddress new@new.com
            $results = Get-DbaAgentOperator -SqlInstance $instance2 -Operator new
            $results.Count | Should -Be 1
            $results.EmailAddress | Should -Be "new@new.com"
        }
    }
}
