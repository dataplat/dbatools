#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaAgentOperator",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
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
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $global:testInstance = Connect-DbaInstance -SqlInstance $TestConfig.instance2 -Database msdb
        $global:testInstance.Invoke("EXEC msdb.dbo.sp_add_operator @name=N'dbatools dba', @enabled=1, @pager_days=0")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaAgentOperator -SqlInstance $global:testInstance -Operator "new" -Confirm:$false -ErrorAction SilentlyContinue
        $null = Remove-DbaAgentOperator -SqlInstance $global:testInstance -Operator "dbatools dba" -Confirm:$false -ErrorAction SilentlyContinue
    }

    Context "When modifying agent operators" {
        It "Should change the name and email" {
            $splatSetOperator = @{
                Name         = "new"
                EmailAddress = "new@new.com"
            }
            $results = Get-DbaAgentOperator -SqlInstance $global:testInstance -Operator "dbatools dba" | Set-DbaAgentOperator @splatSetOperator
            $results = Get-DbaAgentOperator -SqlInstance $global:testInstance -Operator "new"
            $results.Status.Count | Should -Be 1
            $results.EmailAddress | Should -Be "new@new.com"
        }
    }
}