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
        }

        It "leaves the connection open" {
            $callerServer.ConnectionContext.IsOpen | Should -BeTrue
        }

        It "leaves the connection open, so the session survives" {
            { $callerServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM #dbatoolsci_marker") } | Should -Not -Throw
        }

        It "warns that a restart may be needed" {
            $WarnVar | Should -Match "Some configuration options will be updated once SQL Server is restarted"
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
        }

        It "reads the option as enabled before the import" {
            $showAdvancedOptionsBefore | Should -Be 1
        }

        It "leaves the option on the server object of the caller as it was" {
            $advancedServer.Configuration.ShowAdvancedOptions.ConfigValue | Should -Be $showAdvancedOptionsBefore
        }
    }

    Context "Both connections of the caller are left alone when copying (#10554)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Source and destination are the same instance on purpose: every value copied is the value that is
            # already set, so both connections are exercised without changing the configuration of the lab.
            $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $destinationServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $null = $sourceServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE #dbatoolsci_source_marker (id INT)")
            $null = $destinationServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE #dbatoolsci_destination_marker (id INT)")

            $splatCopy = @{
                Source      = $sourceServer
                Destination = $destinationServer
            }
            $null = Import-DbaSpConfigure @splatCopy

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceServer, $destinationServer | Disconnect-DbaInstance
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

    Context "The command still closes the connections it opens itself" {
        BeforeAll {
            $splatCopyByName = @{
                Source      = $TestConfig.InstanceSingle
                Destination = $TestConfig.InstanceSingle
            }
            $null = Import-DbaSpConfigure @splatCopyByName
        }

        It "does not warn when it connects to the instance by name" {
            $WarnVar | Should -BeNullOrEmpty
        }
    }
}
