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
            $results = Get-DbaAgentOperator -SqlInstance $InstanceSingle -Operator "dbatools dba" | Set-DbaAgentOperator -Name new -EmailAddress new@new.com
            $results = Get-DbaAgentOperator -SqlInstance $InstanceSingle -Operator new
            $results.Count | Should -Be 1
            $results.EmailAddress | Should -Be "new@new.com"
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outputOpName = "dbatoolsci_outputop_$(Get-Random)"
            $outputInstance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $outputInstance.ConnectionContext.ExecuteNonQuery("EXEC msdb.dbo.sp_add_operator @name=N'$outputOpName', @enabled=1, @pager_days=0")
            $outputResult = Set-DbaAgentOperator -SqlInstance $TestConfig.InstanceSingle -Operator $outputOpName -EmailAddress "outputtest@test.com"
        }

        AfterAll {
            $outputInstance.ConnectionContext.ExecuteNonQuery("EXEC msdb.dbo.sp_delete_operator @name=N'$outputOpName'") 2>$null
        }

        It "Returns output of the documented type" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Agent.Operator"
        }

        It "Has the correct properties on the output object" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $outputResult[0].PSObject.Properties.Name | Should -Contain "Name"
            $outputResult[0].PSObject.Properties.Name | Should -Contain "EmailAddress"
            $outputResult[0].PSObject.Properties.Name | Should -Contain "PagerDays"
            $outputResult[0].PSObject.Properties.Name | Should -Contain "ID"
        }
    }
}