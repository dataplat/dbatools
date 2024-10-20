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

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Operator",
            "Name",
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
            "InputObject",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
