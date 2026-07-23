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

        $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -Database msdb
        $InstanceSingle.Invoke("EXEC msdb.dbo.sp_add_operator @name=N'dbatools dba', @enabled=1, @pager_days=0")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaAgentOperator -SqlInstance $InstanceSingle -Operator new

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Set works" {
        It "Should change the name and email" {
            $results = Get-DbaAgentOperator -SqlInstance $InstanceSingle -Operator "dbatools dba" | Set-DbaAgentOperator -Name new -EmailAddress new@new.com -Confirm:$false
            $results = Get-DbaAgentOperator -SqlInstance $InstanceSingle -Operator new
            $results.Count | Should -Be 1
            $results.EmailAddress | Should -Be "new@new.com"
        }
    }

    Context "Direct -Operator path and WhatIf" {
        BeforeAll {
            # Use a dedicated connection: the shared $InstanceSingle already has a warm SMO Operators
            # collection, and adding this operator with raw T-SQL bypasses SMO, so a warm cache would
            # not see it. A fresh server object enumerates operators for the first time on demand.
            $directServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -Database msdb
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $directServer.Invoke("EXEC msdb.dbo.sp_add_operator @name=N'dbatools direct', @enabled=1, @pager_days=0")
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaAgentOperator -SqlInstance $directServer -Operator "dbatools direct"
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should change the email when the operator is named directly rather than piped" {
            $results = Set-DbaAgentOperator -SqlInstance $directServer -Operator "dbatools direct" -EmailAddress direct@new.com -Confirm:$false
            $results.EmailAddress | Should -Be "direct@new.com"
        }

        It "Should not change the email when -WhatIf is used" {
            Set-DbaAgentOperator -SqlInstance $directServer -Operator "dbatools direct" -EmailAddress whatif@nope.com -WhatIf
            # Read back over a fresh connection so a WhatIf that wrongly mutated cannot be masked by a cache.
            $freshServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -Database msdb
            $results = Get-DbaAgentOperator -SqlInstance $freshServer -Operator "dbatools direct"
            $results.EmailAddress | Should -Not -Be "whatif@nope.com"
        }
    }
}