#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbMirrorMonitor",
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

        $db = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database msdb
        if (($db.Tables["dbm_monitor_data"].Name)) {
            $putback = $true
        } else {
            $null = Add-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if ($putback) {
            # add it back
            $results = Add-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "removes the mirror monitor" {
        $results = Remove-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue
        $results.MonitorStatus | Should -Be "Removed"
    }

    Context "Output validation" {
        It "Returns output with the correct properties" {
            # Ensure monitor is in a known good state using direct SQL
            $outputServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            try { $outputServer.Query("EXEC msdb.dbo.sp_dbmmonitordropmonitoring") } catch { <# may not exist #> }
            $outputServer.Query("EXEC msdb.dbo.sp_dbmmonitoraddmonitoring")
            $outputResult = @(Remove-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceSingle -Confirm:$false -EnableException:$false | Where-Object { $null -ne $PSItem })

            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0] | Should -BeOfType PSCustomObject
            $outputResult[0].ComputerName | Should -Not -BeNullOrEmpty
            $outputResult[0].InstanceName | Should -Not -BeNullOrEmpty
            $outputResult[0].SqlInstance | Should -Not -BeNullOrEmpty
            $outputResult[0].MonitorStatus | Should -Be "Removed"
        }
    }
}