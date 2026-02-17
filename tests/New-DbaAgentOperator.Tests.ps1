#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaAgentOperator",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $email1 = "test1$($random)@test.com"
        $email2 = "test2$($random)@test.com"
        $email3 = "test3$($random)@test.com"
        $email4 = "test4$($random)@test.com"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaAgentOperator -SqlInstance $server2 -Operator $email1
        $null = Remove-DbaAgentOperator -SqlInstance $server2 -Operator $email2
        $null = Remove-DbaAgentOperator -SqlInstance $server2 -Operator $email3
        $null = Remove-DbaAgentOperator -SqlInstance $server2 -Operator $email4

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "New Agent Operator is added properly" {
        It "Should have the right name" {
            $splatOperator1 = @{
                SqlInstance  = $server2
                Operator     = $email1
                EmailAddress = $email1
                PagerDay     = "Everyday"
                Force        = $true
            }
            $results = New-DbaAgentOperator @splatOperator1 -OutVariable "global:dbatoolsciOutput"
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
            $splatOperatorFull = @{
                SqlInstance       = $server2
                Operator          = $email4
                EmailAddress      = $email4
                NetSendAddress    = "dbauser1"
                PagerAddress      = "dbauser1@pager.dbatools.io"
                PagerDay          = "Everyday"
                SaturdayStartTime = "070000"  # <- Add quotes
                SaturdayEndTime   = "180000"  # <- Add quotes
                SundayStartTime   = "080000"  # <- Add quotes
                SundayEndTime     = "170000"  # <- Add quotes
                WeekdayStartTime  = "060000"  # <- Add quotes
                WeekdayEndTime    = "190000"  # <- Add quotes
            }
            $results = New-DbaAgentOperator @splatOperatorFull
            $results.Enabled | Should -Be $true
            $results.Name | Should -Be $email4
            $results.EmailAddress | Should -Be $email4
            $results.NetSendAddress | Should -Be "dbauser1"
            $results.PagerAddress | Should -Be "dbauser1@pager.dbatools.io"
            $results.PagerDays | Should -Be "Everyday"
            $results.SaturdayPagerStartTime.ToString() | Should -Be "07:00:00"
            $results.SaturdayPagerEndTime.ToString() | Should -Be "18:00:00"
            $results.SundayPagerStartTime.ToString() | Should -Be "08:00:00"
            $results.SundayPagerEndTime.ToString() | Should -Be "17:00:00"
            $results.WeekdayPagerStartTime.ToString() | Should -Be "06:00:00"
            $results.WeekdayPagerEndTime.ToString() | Should -Be "19:00:00"
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