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
}
