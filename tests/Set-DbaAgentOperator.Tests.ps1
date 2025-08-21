#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaAgentOperator",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
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
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $instance2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2 -Database msdb
        $instance2.Invoke("EXEC msdb.dbo.sp_add_operator @name=N'dbatools dba', @enabled=1, @pager_days=0")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaAgentOperator -SqlInstance $instance2 -Operator new

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Set works" {
        It "Should change the name and email" {
            $results = Get-DbaAgentOperator -SqlInstance $instance2 -Operator "dbatools dba" | Set-DbaAgentOperator -Name new -EmailAddress new@new.com
            $results = Get-DbaAgentOperator -SqlInstance $instance2 -Operator new
            $results.Count | Should -Be 1
            $results.EmailAddress | Should -Be "new@new.com"
        }
    }
}