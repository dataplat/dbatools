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
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # The command requires SQL Server 2016+ (MinimumVersion 13). A fresh user database always
        # carries a QueryStoreOptions object (ActualState Off by default), which is all these
        # read-only shape/view assertions need. Capture the version so the version-specific default
        # display set can be checked precisely.
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $versionMajor = $server.VersionMajor

        $testDb = "dbatoolsci_qso_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $testDb

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        try {
            $splatRemove = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $testDb
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaDatabase @splatRemove
        } finally {
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    # The command requires SQL 2016+ (MinimumVersion 13); the dbatools.database lab instance meets
    # this. A -Skip guard cannot be used here because a Context -Skip is evaluated at discovery time,
    # before BeforeAll connects, so $versionMajor is not yet known - the version-specific assertions
    # below adapt at run time instead.
    Context "Reading Query Store options" {
        It "Returns a QueryStoreOptions object with connection note properties for the database" {
            $result = Get-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceSingle -Database $testDb
            $result | Should -Not -BeNullOrEmpty
            # the base object is the SMO QueryStoreOptions, decorated with connection context
            $result | Should -BeOfType Microsoft.SqlServer.Management.Smo.QueryStoreOptions
            $result.Database | Should -Be $testDb
            foreach ($prop in "ComputerName", "InstanceName", "SqlInstance", "Database") {
                $result.PSObject.Properties.Name | Should -Contain $prop
            }
            # identity columns are sourced from the connected server, not just present
            $result.ComputerName | Should -Be $server.ComputerName
            $result.InstanceName | Should -Be $server.ServiceName
            $result.SqlInstance | Should -Be $server.DomainInstanceName
        }

        It "Filters to the requested database with -Database" {
            $result = @(Get-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceSingle -Database $testDb)
            $result.Count | Should -Be 1
            $result[0].Database | Should -Be $testDb
        }

        It "Omits the excluded database with -ExcludeDatabase" {
            # Request master AND the test db while excluding the test db: exactly master must come
            # back, so the assertion cannot pass vacuously on an empty result.
            $splatExclude = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = @("master", $testDb)
                ExcludeDatabase = $testDb
            }
            $result = @(Get-DbaDbQueryStoreOption @splatExclude)
            $result.Count | Should -Be 1
            $result[0].Database | Should -Be "master"
            $result.Database | Should -Not -Contain $testDb
        }

        It "Sets the default view to exactly the version-appropriate columns" {
            $result = Get-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceSingle -Database $testDb
            # the common columns present on every supported version (2016+)
            $expectedView = @(
                "ComputerName", "InstanceName", "SqlInstance", "Database", "ActualState",
                "DataFlushIntervalInSeconds", "StatisticsCollectionIntervalInMinutes",
                "MaxStorageSizeInMB", "CurrentStorageSizeInMB", "QueryCaptureMode",
                "SizeBasedCleanupMode", "StaleQueryThresholdInDays"
            )
            # 2017 (v14) adds the wait-stats/plan columns; 2019+ (v15+) adds the custom capture policy columns
            if ($versionMajor -ge 14) {
                $expectedView += @("MaxPlansPerQuery", "WaitStatsCaptureMode")
            }
            if ($versionMajor -ge 15) {
                $expectedView += @(
                    "CustomCapturePolicyExecutionCount", "CustomCapturePolicyTotalCompileCPUTimeMS",
                    "CustomCapturePolicyTotalExecutionCPUTimeMS", "CustomCapturePolicyStaleThresholdHours"
                )
            }
            $defaultProps = $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            # -SyncWindow 0 makes the comparison positional, so a reordered display view (not just a
            # missing/extra column) is also caught.
            Compare-Object -ReferenceObject $expectedView -DifferenceObject $defaultProps -SyncWindow 0 | Should -BeNullOrEmpty
        }
    }
}