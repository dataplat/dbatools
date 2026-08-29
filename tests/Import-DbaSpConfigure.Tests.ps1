#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Import-DbaSpConfigure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "Destination",
                "SourceSqlCredential",
                "DestinationSqlCredential",
                "SqlInstance",
                "Path",
                "SqlCredential",
                "Force",
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

        # The file is exported from the same instance it is imported into again, so that no test changes the
        # configuration of the lab.
        $exportPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $exportPath -ItemType Directory
        $configFile = Export-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -Path $exportPath

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-Item -Path $exportPath -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "A missing file does not eat an iteration of the caller's loop" {
        It "Warns and completes every iteration" {
            # The begin block guards used to run Stop-Function -Continue without an enclosing loop -
            # the continue escaped the command and consumed an iteration of this very loop, so the
            # counter fell short (#10638).
            $loopCount = 0
            foreach ($i in 1..3) {
                $null = Import-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -Path "$exportPath\does-not-exist.sql" -WarningAction SilentlyContinue
                $loopCount++
            }
            $loopCount | Should -Be 3
            $WarnVar | Should -BeLike "*Not Found*"
        }
    }

    Context "The connection of the caller is left alone when importing from a file (#10554)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Only a non-pooled connection can show this. SMO silently reopens a pooled connection, so the test
            # would pass even with the disconnect this is about.
            $callerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $null = $callerServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE #dbatoolsci_marker (id INT)")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # The command always warns about a possible restart, so the warning is silenced and asserted below.
            $splatImport = @{
                SqlInstance   = $callerServer
                Path          = $configFile.FullName
                WarningAction = "SilentlyContinue"
            }
            $null = Import-DbaSpConfigure @splatImport
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $callerServer | Disconnect-DbaInstance

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "leaves the connection open" {
            $callerServer.ConnectionContext.IsOpen | Should -BeTrue
        }

        It "leaves the connection open, so the session survives" {
            { $callerServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM #dbatoolsci_marker") } | Should -Not -Throw
        }

        It "warns that a restart may be needed" {
            # The warning about the restart is the last one. On instances where the edition does not allow one of
            # the options in the file to be set, the command warns about those lines first.
            $WarnVar[-1] | Should -Match "Some configuration options will be updated once SQL Server is restarted"
        }
    }

    Context "No pending configuration change is left on the server object of the caller (#10554)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The command used to set show advanced options on the Configuration collection of the caller without
            # ever calling Alter(). That only shows while the option is enabled on the instance, because the
            # pending value left behind was 0 while the running value was 1, and the next Alter() of the caller
            # would have applied it.
            $setupServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $originalShowAdvancedOptions = $setupServer.Configuration.ShowAdvancedOptions.ConfigValue
            $setupServer.Configuration.ShowAdvancedOptions.ConfigValue = $true
            $setupServer.Configuration.Alter($true)

            $advancedServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $showAdvancedOptionsBefore = $advancedServer.Configuration.ShowAdvancedOptions.ConfigValue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $splatImportAdvanced = @{
                SqlInstance   = $advancedServer
                Path          = $configFile.FullName
                WarningAction = "SilentlyContinue"
            }
            $null = Import-DbaSpConfigure @splatImportAdvanced
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $advancedServer | Disconnect-DbaInstance

            $setupServer.Configuration.ShowAdvancedOptions.ConfigValue = $originalShowAdvancedOptions
            $setupServer.Configuration.Alter($true)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "reads the option as enabled before the import" {
            $showAdvancedOptionsBefore | Should -Be 1
        }

        It "leaves the option on the server object of the caller as it was" {
            $advancedServer.Configuration.ShowAdvancedOptions.ConfigValue | Should -Be $showAdvancedOptionsBefore
        }
    }

    Context "The copy applies what differs and leaves both callers alone (#10554)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $setupServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

            # The command has to put this back the way it found it, so the test runs with it switched on.
            $originalShowAdvancedOptions = $setupServer.Configuration.ShowAdvancedOptions.ConfigValue
            $setupServer.Configuration.ShowAdvancedOptions.ConfigValue = $true
            $setupServer.Configuration.Alter($true)

            # Source and destination are the same instance, so nothing but the one option below can change and
            # the test does not need a second instance. The two server objects are made to disagree the way two
            # instances would: the source is connected while the option still has the value that is to be
            # copied, the instance is then changed, and only then is the destination connected. SMO reads the
            # configuration once per server object, so each of them keeps the value it saw.
            $originalCostThreshold = $setupServer.Configuration.CostThresholdForParallelism.RunValue
            $changedCostThreshold = $originalCostThreshold + 7

            $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $null = $sourceServer.Configuration.Properties.Count
            $null = $sourceServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE #dbatoolsci_source_marker (id INT)")

            $setupServer.Configuration.CostThresholdForParallelism.ConfigValue = $changedCostThreshold
            $setupServer.Configuration.Alter($true)

            $destinationServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $null = $destinationServer.Configuration.Properties.Count
            $null = $destinationServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE #dbatoolsci_destination_marker (id INT)")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $null = Import-DbaSpConfigure -Source $sourceServer -Destination $destinationServer

            # Every other command below writes to $WarnVar as well, so it has to be kept here.
            $copyWarnings = $WarnVar

            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $configurationQuery = @"
SELECT name, value, value_in_use FROM sys.configurations WHERE name IN ('cost threshold for parallelism', 'show advanced options')
"@
            $configurationAfter = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query $configurationQuery
            $costThresholdAfter = ($configurationAfter | Where-Object name -eq "cost threshold for parallelism").value_in_use
            $showAdvancedOptionsAfter = ($configurationAfter | Where-Object name -eq "show advanced options").value_in_use

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceServer, $destinationServer | Disconnect-DbaInstance

            $setupServer.Configuration.Refresh()
            $setupServer.Configuration.CostThresholdForParallelism.ConfigValue = $originalCostThreshold
            $setupServer.Configuration.ShowAdvancedOptions.ConfigValue = $originalShowAdvancedOptions
            $setupServer.Configuration.Alter($true)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "copies the option the two instances disagree about" {
            $costThresholdAfter | Should -Be $originalCostThreshold
        }

        It "leaves show advanced options the way it found it" {
            $showAdvancedOptionsAfter | Should -Be 1
        }

        It "does not warn, because the option that changed takes effect without a restart" {
            $copyWarnings | Should -BeNullOrEmpty
        }

        It "leaves the source connection open" {
            $sourceServer.ConnectionContext.IsOpen | Should -BeTrue
        }

        It "leaves the destination connection open" {
            $destinationServer.ConnectionContext.IsOpen | Should -BeTrue
        }

        It "leaves the source connection open, so the session survives" {
            { $sourceServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM #dbatoolsci_source_marker") } | Should -Not -Throw
        }

        It "leaves the destination connection open, so the session survives" {
            { $destinationServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM #dbatoolsci_destination_marker") } | Should -Not -Throw
        }
    }

    Context "The command still closes the connection it opens itself" {
        BeforeAll {
            # Passing the name instead of a server object is the other side of the guard: the command opens the
            # connection here, so it is the one that has to close it again.
            $splatImportByName = @{
                SqlInstance   = $TestConfig.InstanceSingle
                Path          = $configFile.FullName
                WarningAction = "SilentlyContinue"
            }
            $null = Import-DbaSpConfigure @splatImportByName
        }

        It "runs to the end and warns that a restart may be needed" {
            $WarnVar[-1] | Should -Match "Some configuration options will be updated once SQL Server is restarted"
        }
    }
}
