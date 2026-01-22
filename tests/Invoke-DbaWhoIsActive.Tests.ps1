#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaWhoIsActive",
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
                "Filter",
                "FilterType",
                "NotFilter",
                "NotFilterType",
                "ShowOwnSpid",
                "ShowSystemSpids",
                "ShowSleepingSpids",
                "GetFullInnerText",
                "GetPlans",
                "GetOuterCommand",
                "GetTransactionInfo",
                "GetTaskInfo",
                "GetLocks",
                "GetAverageTime",
                "GetAdditonalInfo",
                "FindBlockLeaders",
                "DeltaInterval",
                "OutputColumnList",
                "SortOrder",
                "FormatOutput",
                "DestinationTable",
                "ReturnSchema",
                "Schema",
                "Help",
                "As",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:$env:appveyor {
    # Skip IntegrationTests on AppVeyor because they fail for unknown reasons.

    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $testzippath = "$($TestConfig.appveyorlabrepo)\CommunitySoftware\sp_whoisactive-12.00.zip"
        $resultInstallMaster = Install-DbaWhoIsActive -SqlInstance $TestConfig.InstanceSingle -LocalFile $testzippath -Database master
        $resultInstallTempdb = Install-DbaWhoIsActive -SqlInstance $TestConfig.InstanceSingle -LocalFile $testzippath -Database tempdb

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query "DROP PROCEDURE [dbo].[sp_WhoIsActive];" -ErrorAction SilentlyContinue
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database tempdb -Query "DROP PROCEDURE [dbo].[sp_WhoIsActive];" -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    Context "Should have SPWhoisActive installed correctly" {
        It "Should be installed to master" {
            $resultInstallMaster.Name | Should -Be "sp_WhoisActive"
        }
        It "Should be installed to tempdb" {
            $resultInstallTempdb.Name | Should -Be "sp_WhoisActive"
        }
    }
    Context "Should Execute SPWhoisActive" {
        It "Should execute and return Help" {
            $resultsHelp = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.InstanceSingle -Help
            $WarnVar | Should -BeNullOrEmpty
            $resultsHelp | Should -Not -BeNullOrEmpty
        }

        It "Should execute with no parameters in default location" {
            $resultsDefault = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.InstanceSingle
            $WarnVar | Should -BeNullOrEmpty
            # No test for results as we don't expect any running queries
        }

        It "Should execute with ShowSleepingSpids" -Skip {
            # Skip It because it warns: Failed during execution | Name cannot begin with the ' ' character, hexadecimal value 0x20. Line 5372, position 60.
            # TODO: The command runs correct in an interactive session and only fails if executed by pester

            $resultsSleeping = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.InstanceSingle -ShowSleepingSpids 2
            $WarnVar | Should -BeNullOrEmpty
            $resultsSleeping | Should -Not -BeNullOrEmpty
        }

        It "Should execute with no parameters against alternate install location" {
            $resultsTempdb = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.InstanceSingle -Database tempdb
            $WarnVar | Should -BeNullOrEmpty
            # No test for results as we don't expect any running queries
        }

        It "Should execute with ShowOwnSpid" {
            $resultsOwnSpid = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.InstanceSingle -ShowOwnSpid
            $WarnVar | Should -BeNullOrEmpty
            $resultsOwnSpid | Should -Not -BeNullOrEmpty
        }

        It "Should execute with ShowSystemSpids" {
            $resultsSystemSpids = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.InstanceSingle -ShowSystemSpids
            $WarnVar | Should -BeNullOrEmpty
            $resultsSystemSpids | Should -Not -BeNull
        }

        It "Should execute with averagetime" {
            $resultsAverageTime = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.InstanceSingle -Database Tempdb -GetAverageTime
            $WarnVar | Should -BeNullOrEmpty
            # No test for results as we don't expect any running queries
        }

        It "Should execute with GetOuterCommand and FindBlockLeaders" {
            $resultsOuterCommand = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.InstanceSingle -GetOuterCommand -FindBlockLeaders
            $WarnVar | Should -BeNullOrEmpty
            # No test for results as we don't expect any running queries
        }

        It "Should execute with NotFilter and NotFilterType" {
            $resultsNotFilter = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.InstanceSingle -NotFilter 0 -NotFilterType Program
            $WarnVar | Should -BeNullOrEmpty
            # No test for results as we don't expect any running queries
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.InstanceSingle -ShowOwnSpid -EnableException
        }

        It "Returns DataRow by default" {
            $result | Should -BeOfType [System.Data.DataRow]
        }

        It "Has core sp_WhoIsActive columns" {
            $columnNames = $result.Table.Columns.ColumnName
            $columnNames | Should -Contain 'session_id'
            $columnNames | Should -Contain 'sql_text'
        }
    }

    Context "Output with -As PSObject" {
        BeforeAll {
            $result = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.InstanceSingle -ShowOwnSpid -As PSObject -EnableException
        }

        It "Returns PSCustomObject when -As PSObject specified" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has core sp_WhoIsActive properties" {
            $result.PSObject.Properties.Name | Should -Contain 'session_id'
            $result.PSObject.Properties.Name | Should -Contain 'sql_text'
        }
    }

    Context "Output with -As DataTable" {
        BeforeAll {
            $result = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.InstanceSingle -ShowOwnSpid -As DataTable -EnableException
        }

        It "Returns DataTable when -As DataTable specified" {
            $result | Should -BeOfType [System.Data.DataTable]
        }

        It "Has core sp_WhoIsActive columns" {
            $result.Columns.ColumnName | Should -Contain 'session_id'
            $result.Columns.ColumnName | Should -Contain 'sql_text'
        }
    }

    Context "Output with -As DataSet" {
        BeforeAll {
            $result = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.InstanceSingle -ShowOwnSpid -As DataSet -EnableException
        }

        It "Returns DataSet when -As DataSet specified" {
            $result | Should -BeOfType [System.Data.DataSet]
        }

        It "Contains table with core sp_WhoIsActive columns" {
            $result.Tables[0].Columns.ColumnName | Should -Contain 'session_id'
            $result.Tables[0].Columns.ColumnName | Should -Contain 'sql_text'
        }
    }

    Context "Output with -ReturnSchema" {
        BeforeAll {
            $result = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.InstanceSingle -ReturnSchema -EnableException
        }

        It "Returns DataRow containing CREATE TABLE statement" {
            $result | Should -BeOfType [System.Data.DataRow]
        }

        It "Has create_table_sql column" {
            $result.Table.Columns.ColumnName | Should -Contain 'create_table_sql'
        }
    }
}