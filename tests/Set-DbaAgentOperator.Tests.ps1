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

    Context "When the instance cannot be reached" {
        BeforeAll {
            # Lower the connection timeout so the three failing connection attempts stay fast.
            $oldConnectionTimeout = Get-DbatoolsConfigValue -FullName sql.connection.timeout
            $null = Set-DbatoolsConfig -FullName sql.connection.timeout -Value 2
        }

        AfterAll {
            $null = Set-DbatoolsConfig -FullName sql.connection.timeout -Value $oldConnectionTimeout
        }

        It "Warns without eating an iteration of the caller's loop" {
            # The connection catch used to run Stop-Function -Continue before the operator loop -
            # the continue escaped the command and consumed an iteration of this very loop, so the
            # counter fell short (#10638).
            $loopCount = 0
            foreach ($i in 1..3) {
                $splatUnreachable = @{
                    SqlInstance   = "dbatoolsci-nohost"
                    Operator      = "dbatoolsci_nope"
                    EmailAddress  = "nope@nope.com"
                    WarningAction = "SilentlyContinue"
                }
                $null = Set-DbaAgentOperator @splatUnreachable
                $loopCount++
            }
            $loopCount | Should -Be 3
            ($WarnVar -join " ") | Should -BeLike "*Failed*"
        }
    }
}