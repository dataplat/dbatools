#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbQueryStoreOption",
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
                "Database",
                "ExcludeDatabase",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    BeforeDiscovery {
        # MAX_PLANS_PER_QUERY arrived with SQL Server 2017, so the scenario below cannot be built before
        # that. The value decides a Skip, which Pester needs while it discovers the tests, so it cannot be
        # read in BeforeAll.
        $discoveryServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $instanceVersionMajor = $discoveryServer.VersionMajor
        $null = $discoveryServer | Disconnect-DbaInstance

        # Azure SQL Database reports product version 12.0 while SMO reads VersionMajor 18 there, so it is the
        # engine where the Query Store options were decided by accident before #10600. No CI environment has
        # one; a lab configuration supplies it through AzureSqlDbServer and everywhere else the Context skips.
        $hasAzureSqlDb = -not [string]::IsNullOrWhiteSpace($TestConfig.AzureSqlDbServer)
    }

    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $serverSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        # Created here rather than in the Context that uses it, because the Contexts below read Query Store
        # on model and leave a session parked in it, and the next CREATE DATABASE then fails with
        # "Could not obtain exclusive lock on database 'model'". That is the leak of #10584, and until it
        # is merged the only way past it is to create the database before anything has touched model.
        $queryStoreDbName = "dbatoolsci_qso_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $queryStoreDbName
        $null = Set-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceSingle -Database $queryStoreDbName -State ReadWrite

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $queryStoreDbName -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When a system database is named explicitly" {
        It "Warns about master and tempdb instead of silently returning nothing" {
            $resultsSystemDb = Get-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceSingle -Database master, tempdb -WarningVariable warnSystemDb -WarningAction SilentlyContinue
            $resultsSystemDb | Should -BeNullOrEmpty
            $warnSystemDb -join "`n" | Should -Match "Query Store cannot be enabled on system database master"
            $warnSystemDb -join "`n" | Should -Match "Query Store cannot be enabled on system database tempdb"
        }

        It "Reads model from SQL Server 2022 on and warns about it before that" {
            # Silenced because the pre-2022 branch below expects a warning. The warning is still
            # captured in $warnModel, so an unexpected one on 2022 and later fails the assertion.
            $resultsModel = Get-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceSingle -Database model -WarningVariable warnModel -WarningAction SilentlyContinue

            if ($serverSingle.VersionMajor -ge 16) {
                $resultsModel.Database | Should -Be "model"
                $warnModel | Should -BeNullOrEmpty
            } else {
                $resultsModel | Should -BeNullOrEmpty
                $warnModel -join "`n" | Should -Match "Query Store cannot be read on model before SQL Server 2022"
            }
        }
    }

    Context "When no database is named" {
        It "Keeps model out of the sweep so instance defaults are never changed by accident" {
            $resultsSweep = Get-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceSingle -WarningVariable warnSweep
            $resultsSweep.Database | Should -Not -Contain "model"
            $warnSweep | Should -BeNullOrEmpty
        }
    }

    Context "When a value is available from SMO" -Skip:($instanceVersionMajor -lt 14) {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The database itself comes from the BeforeAll of the Describe, see the note there.
            $resultsFromSmo = Get-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceSingle -Database $queryStoreDbName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Leaves MaxPlansPerQuery and WaitStatsCaptureMode as the properties of the SMO object" {
            # Both are real properties of QueryStoreOptions. Adding them with Add-Member replaces the
            # property with a note property on the object of the caller - one that keeps its value even
            # after the object is refreshed - so only values SMO does not carry may be added that way.
            # See #10562. This guards the rule rather than a fix: on SQL Server 2019 and later the two
            # were queried and then discarded, so nothing observable changed there. It is SQL Server 2017
            # where they used to be added over the real property, and the lab has no 2017 instance.
            (Get-Member -InputObject $resultsFromSmo -Name MaxPlansPerQuery).MemberType | Should -Be "Property"
            (Get-Member -InputObject $resultsFromSmo -Name WaitStatsCaptureMode).MemberType | Should -Be "Property"
        }

        It "Still reports both of them" {
            $resultsFromSmo.MaxPlansPerQuery | Should -Not -BeNullOrEmpty
            $resultsFromSmo.WaitStatsCaptureMode | Should -Not -BeNullOrEmpty
        }

        It "Adds the CustomCapturePolicy values, which SMO does not carry" -Skip:($instanceVersionMajor -lt 15) {
            (Get-Member -InputObject $resultsFromSmo -Name CustomCapturePolicyExecutionCount).MemberType | Should -Be "NoteProperty"
        }
    }

    Context "When the default columns are chosen" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $resultsColumns = Get-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceSingle -Database $queryStoreDbName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $baseColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "ActualState",
                "DataFlushIntervalInSeconds",
                "StatisticsCollectionIntervalInMinutes",
                "MaxStorageSizeInMB",
                "CurrentStorageSizeInMB",
                "QueryCaptureMode",
                "SizeBasedCleanupMode",
                "StaleQueryThresholdInDays"
            )
            $waitStatsColumns = @(
                "MaxPlansPerQuery",
                "WaitStatsCaptureMode"
            )
            $customCapturePolicyColumns = @(
                "CustomCapturePolicyExecutionCount",
                "CustomCapturePolicyTotalCompileCPUTimeMS",
                "CustomCapturePolicyTotalExecutionCPUTimeMS",
                "CustomCapturePolicyStaleThresholdHours"
            )
        }

        It "Shows the same columns for the version as before the feature rules took over" {
            # Written out by version here on purpose, so that a wrong feature rule changes the output and fails.
            # See #10600.
            $expectedColumns = $baseColumns
            if ($serverSingle.VersionMajor -ge 14) {
                $expectedColumns += $waitStatsColumns
            }
            if ($serverSingle.VersionMajor -ge 15) {
                $expectedColumns += $customCapturePolicyColumns
            }
            $resultsColumns.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Be $expectedColumns
        }
    }

    Context "When the instance is an Azure SQL Database" -Skip:(-not $hasAzureSqlDb) {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # A serverless database that has been idle is paused and answers the first attempts with error
            # 40613 "is not currently available" while it resumes, so the connection is retried until it is
            # up, and only an error that says something else is thrown immediately.
            $splatAzureConnect = @{
                SqlInstance    = $TestConfig.AzureSqlDbServer
                Database       = $TestConfig.AzureSqlDbName
                SqlCredential  = $TestConfig.AzureSqlDbCred
                ConnectTimeout = 120
            }
            $azureResumeAttempt = 0
            while ($null -eq $serverAzure) {
                $azureResumeAttempt++
                try {
                    $serverAzure = Connect-DbaInstance @splatAzureConnect
                } catch {
                    if ($azureResumeAttempt -ge 10 -or $PSItem.Exception.Message -notmatch "is not currently available") {
                        throw
                    }
                    Start-Sleep -Seconds 15
                }
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            if ($serverAzure) {
                $null = $serverAzure | Disconnect-DbaInstance
            }
        }

        It "really is an Azure SQL Database, which is what makes this case different" {
            # Guards the tests below: pointed at a SQL Server they would pass without proving anything.
            $serverAzure.DatabaseEngineEdition | Should -Be "SqlDatabase"
            $serverAzure.Version.Major | Should -Be 12
        }

        It "Shows every Query Store option, which Azure SQL Database has whatever its version says" {
            $resultsAzure = Get-DbaDbQueryStoreOption -SqlInstance $serverAzure -Database $TestConfig.AzureSqlDbName -WarningVariable warnAzure
            $warnAzure | Should -BeNullOrEmpty
            $resultsAzure.Database | Should -Be $TestConfig.AzureSqlDbName
            $resultsAzure.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Contain "WaitStatsCaptureMode"
            $resultsAzure.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Contain "CustomCapturePolicyExecutionCount"
        }

        It "Warns that there is no model to read instead of blaming the version" {
            # Before #10600 model counted as supported here because VersionMajor is 18, and the named model then
            # silently returned nothing, because an Azure SQL Database has no model a user can reach.
            $resultsModel = Get-DbaDbQueryStoreOption -SqlInstance $serverAzure -Database model -WarningVariable warnModel -WarningAction SilentlyContinue
            $resultsModel | Should -BeNullOrEmpty
            $warnModel -join "`n" | Should -Match "Azure SQL Database has no model database"
        }
    }
}