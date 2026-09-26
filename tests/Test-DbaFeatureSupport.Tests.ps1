#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaFeatureSupport",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

BeforeDiscovery {
    # Azure SQL Database is the engine where a VersionMajor comparison answers by accident: SMO reads 18 there
    # while the product version is 12.0. No CI environment has one; a lab configuration supplies it through
    # AzureSqlDbServer and everywhere else that Context skips itself. The value decides a Skip, so it has to
    # exist at discovery time.
    $script:hasAzureSqlDb = -not [string]::IsNullOrWhiteSpace($TestConfig.AzureSqlDbServer)
}

Describe $CommandName -Tag UnitTests {
    BeforeDiscovery {
        # The rules for engines and versions no test instance provides - Managed Instance, SQL Server 2016 RTM,
        # a server object with missing metadata. These supplement the integration tests below against real
        # servers; they do not replace them.
        $sql2014 = @{ DatabaseEngineType = "Standalone"; DatabaseEngineEdition = "Enterprise"; Version = [version]"12.0.6024.0" }
        $sql2016 = @{ DatabaseEngineType = "Standalone"; DatabaseEngineEdition = "Enterprise"; Version = [version]"13.0.1601.5" }
        $sql2017 = @{ DatabaseEngineType = "Standalone"; DatabaseEngineEdition = "Standard"; Version = [version]"14.0.1000.169" }
        $sql2019 = @{ DatabaseEngineType = "Standalone"; DatabaseEngineEdition = "Express"; Version = [version]"15.0.2000.5" }
        $sql2022 = @{ DatabaseEngineType = "Standalone"; DatabaseEngineEdition = "Enterprise"; Version = [version]"16.0.1000.6" }
        $azureSqlDb = @{ DatabaseEngineType = "SqlAzureDatabase"; DatabaseEngineEdition = "SqlDatabase"; Version = [version]"12.0.2000.8" }
        $managedInstance = @{ DatabaseEngineType = "Standalone"; DatabaseEngineEdition = "SqlManagedInstance"; Version = [version]"12.0.2000.8" }

        $ruleCases = @(
            @{ Label = "SQL Server 2014"; ServerProperty = $sql2014; Feature = "QueryStore"; Expected = $false }
            @{ Label = "SQL Server 2016 RTM"; ServerProperty = $sql2016; Feature = "QueryStore"; Expected = $true }
            @{ Label = "SQL Server 2016 RTM"; ServerProperty = $sql2016; Feature = "QueryStoreWaitStats"; Expected = $false }
            @{ Label = "SQL Server 2016 RTM"; ServerProperty = $sql2016; Feature = "QueryStoreMaxPlansPerQuery"; Expected = $false }
            @{ Label = "SQL Server 2017"; ServerProperty = $sql2017; Feature = "QueryStoreWaitStats"; Expected = $true }
            @{ Label = "SQL Server 2017"; ServerProperty = $sql2017; Feature = "QueryStoreMaxPlansPerQuery"; Expected = $true }
            @{ Label = "SQL Server 2017"; ServerProperty = $sql2017; Feature = "QueryStoreCustomCapturePolicy"; Expected = $false }
            @{ Label = "SQL Server 2019 Express"; ServerProperty = $sql2019; Feature = "QueryStoreCustomCapturePolicy"; Expected = $true }
            @{ Label = "SQL Server 2019 Express"; ServerProperty = $sql2019; Feature = "QueryStoreOnModel"; Expected = $false }
            @{ Label = "SQL Server 2022"; ServerProperty = $sql2022; Feature = "QueryStoreOnModel"; Expected = $true }
            @{ Label = "Azure SQL Database"; ServerProperty = $azureSqlDb; Feature = "QueryStore"; Expected = $true }
            @{ Label = "Azure SQL Database"; ServerProperty = $azureSqlDb; Feature = "QueryStoreCustomCapturePolicy"; Expected = $true }
            @{ Label = "Azure SQL Database"; ServerProperty = $azureSqlDb; Feature = "QueryStoreOnModel"; Expected = $false }
            @{ Label = "Managed Instance"; ServerProperty = $managedInstance; Feature = "QueryStoreCustomCapturePolicy"; Expected = $true }
            @{ Label = "Managed Instance"; ServerProperty = $managedInstance; Feature = "QueryStoreOnModel"; Expected = $true }
        )

        $unreadableCases = @(
            @{ Label = "no version"; ServerProperty = @{ DatabaseEngineType = "Standalone"; DatabaseEngineEdition = "Enterprise"; Version = $null }; ExpectedError = "Cannot read the version" }
            @{ Label = "version 0.0"; ServerProperty = @{ DatabaseEngineType = "Standalone"; DatabaseEngineEdition = "Enterprise"; Version = [version]"0.0" }; ExpectedError = "Cannot read the version" }
            @{ Label = "no engine type"; ServerProperty = @{ DatabaseEngineType = $null; DatabaseEngineEdition = "Enterprise"; Version = [version]"16.0.1000.6" }; ExpectedError = "Cannot read the engine" }
            @{ Label = "an unknown engine type"; ServerProperty = @{ DatabaseEngineType = "Unknown"; DatabaseEngineEdition = "Enterprise"; Version = [version]"16.0.1000.6" }; ExpectedError = "Cannot read the engine" }
            @{ Label = "no engine edition"; ServerProperty = @{ DatabaseEngineType = "Standalone"; DatabaseEngineEdition = $null; Version = [version]"16.0.1000.6" }; ExpectedError = "Cannot read the engine" }
            @{ Label = "an engine without rules"; ServerProperty = @{ DatabaseEngineType = "SqlAzureDatabase"; DatabaseEngineEdition = "SqlDataWarehouse"; Version = [version]"10.0.0.0" }; ExpectedError = "There is no rule" }
        )
    }

    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Server",
                "Feature"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Rules per engine" {
        It "Answers <Expected> for <Feature> on <Label>" -ForEach $ruleCases {
            Test-DbaFeatureSupport -Server ([PSCustomObject]$ServerProperty) -Feature $Feature | Should -BeExactly $Expected
        }
    }

    Context "Inputs it refuses to guess about" {
        It "Throws on a server object with <Label>" -ForEach $unreadableCases {
            { Test-DbaFeatureSupport -Server ([PSCustomObject]$ServerProperty) -Feature QueryStore } | Should -Throw "*$ExpectedError*"
        }

        It "Throws on a feature name it does not know" {
            $server2022 = [PSCustomObject]@{ DatabaseEngineType = "Standalone"; DatabaseEngineEdition = "Enterprise"; Version = [version]"16.0.1000.6" }
            { Test-DbaFeatureSupport -Server $server2022 -Feature QueryStoreTypo } | Should -Throw "*Unknown feature QueryStoreTypo*"
        }

        It "Throws on an instance name instead of connecting to it" {
            { Test-DbaFeatureSupport -Server "sql01" -Feature QueryStore } | Should -Throw "*needs a connected server object*"
            { Test-DbaFeatureSupport -Server ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]"sql01") -Feature QueryStore } | Should -Throw "*needs a connected server object*"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeDiscovery {
        # From which major version on each feature exists on SQL Server, written out here independently of the
        # rule table so that a wrong entry there fails a test instead of being compared with itself.
        $sqlServerCases = @(
            @{ Feature = "QueryStore"; FirstMajor = 13 }
            @{ Feature = "QueryStoreWaitStats"; FirstMajor = 14 }
            @{ Feature = "QueryStoreMaxPlansPerQuery"; FirstMajor = 14 }
            @{ Feature = "QueryStoreCustomCapturePolicy"; FirstMajor = 15 }
            @{ Feature = "QueryStoreOnModel"; FirstMajor = 16 }
        )

        $azureCases = @(
            @{ Feature = "QueryStore"; Expected = $true }
            @{ Feature = "QueryStoreWaitStats"; Expected = $true }
            @{ Feature = "QueryStoreMaxPlansPerQuery"; Expected = $true }
            @{ Feature = "QueryStoreCustomCapturePolicy"; Expected = $true }
            @{ Feature = "QueryStoreOnModel"; Expected = $false }
        )
    }

    Context "On SQL Server" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $serverSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Answers <Feature> by the version of the connected server" -ForEach $sqlServerCases {
            $expected = $serverSingle.Version.Major -ge $FirstMajor
            Test-DbaFeatureSupport -Server $serverSingle -Feature $Feature | Should -BeExactly $expected
        }
    }

    Context "On Azure SQL Database" -Skip:(-not $script:hasAzureSqlDb) {
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

        It "really is an Azure SQL Database whose VersionMajor would answer by accident" {
            # Guards the tests below: pointed at anything else they would pass without proving anything.
            $serverAzure.DatabaseEngineEdition | Should -Be "SqlDatabase"
            $serverAzure.Version.Major | Should -Be 12
            $serverAzure.VersionMajor | Should -BeGreaterThan 16
        }

        It "Answers <Expected> for <Feature> by the engine, not by the version" -ForEach $azureCases {
            Test-DbaFeatureSupport -Server $serverAzure -Feature $Feature | Should -BeExactly $Expected
        }
    }
}
