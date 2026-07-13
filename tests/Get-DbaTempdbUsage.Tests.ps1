#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaTempdbUsage",
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
    Context "When retrieving tempdb usage" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # A held-open session with a live temp table gives the DMV join a nonzero
            # net tempdb allocation to report.
            $fixtureServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $fixtureServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE #dbatoolsci_tempdbusage (Filler CHAR(8000)); INSERT INTO #dbatoolsci_tempdbusage SELECT REPLICATE(CHAR(120), 10);") | Out-Null

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $fixtureServer.ConnectionContext.Disconnect()
        }

        It "Returns the fixture session with tempdb allocations" {
            $results = @(Get-DbaTempdbUsage -SqlInstance $TestConfig.InstanceSingle)
            $fixtureRows = @($results | Where-Object Spid -eq $fixtureServer.ConnectionContext.ProcessID)
            $fixtureRows | Should -Not -BeNullOrEmpty
            $fixtureRows[0].TotalUserAllocatedKB | Should -BeGreaterThan 0
        }
    }
}