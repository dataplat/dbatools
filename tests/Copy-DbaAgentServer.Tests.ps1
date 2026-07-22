#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaAgentServer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "DisableJobsOnDestination",
                "DisableJobsOnSource",
                "ExcludeServerProperties",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    It "Runs the full live WhatIf orchestration without changing Agent inventories" {
        $destination = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -EnableException
        $getInventory = {
            $destination.JobServer.Refresh()
            $destination.JobServer.JobCategories.Refresh()
            $destination.JobServer.OperatorCategories.Refresh()
            $destination.JobServer.AlertCategories.Refresh()
            $destination.JobServer.Operators.Refresh()
            $destination.JobServer.ProxyAccounts.Refresh()
            $destination.JobServer.SharedSchedules.Refresh()
            $destination.JobServer.Jobs.Refresh()
            $destination.JobServer.Alerts.Refresh()
            [ordered]@{
                JobCategories      = @($destination.JobServer.JobCategories.Name)
                OperatorCategories = @($destination.JobServer.OperatorCategories.Name)
                AlertCategories    = @($destination.JobServer.AlertCategories.Name)
                Operators          = @($destination.JobServer.Operators.Name)
                Proxies            = @($destination.JobServer.ProxyAccounts.Name)
                Schedules          = @($destination.JobServer.SharedSchedules.Name)
                Jobs               = @($destination.JobServer.Jobs.Name)
                Alerts             = @($destination.JobServer.Alerts.Name)
            } | ConvertTo-Json -Compress
        }

        $before = & $getInventory
        {
            Copy-DbaAgentServer -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -ExcludeServerProperties -WhatIf -EnableException
        } | Should -Not -Throw
        $after = & $getInventory
        $after | Should -BeExactly $before
    }

    It "Surfaces the destination-connect warning instead of swallowing the warning stream" {
        # Distinguishing leg for the 3>&1 warning-stream fix: an unreachable destination raises the friendly
        # Stop-Function connect warning. InvokeScopedStreaming recovers a WarningRecord only when it reaches the
        # output collection, so without the hop closing on '3>&1 2>&1' the entire warning stream is swallowed and
        # -WarningVariable stays empty. A downstream null-ref against the failed destination may follow the warning;
        # the warning is emitted first, so it is captured regardless.
        $connectWarning = $null
        try {
            $null = Copy-DbaAgentServer -Source $TestConfig.InstanceCopy1 -Destination "localhost,9999" -ExcludeServerProperties -WarningVariable connectWarning -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        } catch {
            # unreachable destination may raise downstream errors; the warning stream is what this test asserts
        }
        $connectWarning | Should -Not -BeNullOrEmpty
    }
}
