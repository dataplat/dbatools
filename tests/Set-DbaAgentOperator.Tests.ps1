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
            $results = Get-DbaAgentOperator -SqlInstance $InstanceSingle -Operator "dbatools dba" | Set-DbaAgentOperator -Name new -EmailAddress new@new.com -OutVariable "global:dbatoolsciOutput"
            $results = Get-DbaAgentOperator -SqlInstance $InstanceSingle -Operator new
            $results.Count | Should -Be 1
            $results.EmailAddress | Should -Be "new@new.com"
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.Operator]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "ID",
                "IsEnabled",
                "EmailAddress",
                "LastEmail"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.Agent\.Operator"
        }
    }
}