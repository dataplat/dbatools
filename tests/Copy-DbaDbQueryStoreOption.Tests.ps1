#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaDbQueryStoreOption",
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
                "SourceDatabase",
                "Destination",
                "DestinationSqlCredential",
                "DestinationDatabase",
                "Exclude",
                "AllDatabases",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Verifying query store options are copied" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $server2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Copy the query store options from one db to another on the same instance" {
            # Setup for this specific test
            $db1Name = "dbatoolsci_querystoretest1"
            $db1 = New-DbaDatabase -SqlInstance $server2 -Name $db1Name

            $db1QSOptions = Get-DbaDbQueryStoreOption -SqlInstance $server2 -Database $db1Name
            $originalQSOptionValue = $db1QSOptions.DataFlushIntervalInSeconds
            $updatedQSOption = $db1QSOptions.DataFlushIntervalInSeconds + 1
            $splatSetOptions = @{
                SqlInstance   = $server2
                Database      = $db1Name
                FlushInterval = $updatedQSOption
                State         = "ReadWrite"
            }
            $updatedDB1Options = Set-DbaDbQueryStoreOption @splatSetOptions

            $db2Name = "dbatoolsci_querystoretest2"
            $db2 = New-DbaDatabase -SqlInstance $server2 -Name $db2Name

            # Test assertions
            $db2QSOptions = Get-DbaDbQueryStoreOption -SqlInstance $server2 -Database $db2Name
            $db2QSOptions.DataFlushIntervalInSeconds | Should -Be $originalQSOptionValue

            $splatCopyOptions = @{
                Source              = $server2
                SourceDatabase      = $db1Name
                Destination         = $server2
                DestinationDatabase = $db2Name
            }
            $result = Copy-DbaDbQueryStoreOption @splatCopyOptions

            $result.Status | Should -Be "Successful"
            $result.SourceDatabase | Should -Be $db1Name
            $result.SourceDatabaseID | Should -Be $db1.ID
            $result.Name | Should -Be $db2Name
            $result.DestinationDatabaseID | Should -Be $db2.ID

            $db2QSOptions = Get-DbaDbQueryStoreOption -SqlInstance $server2 -Database $db2Name
            $db2QSOptions.DataFlushIntervalInSeconds | Should -Be ($originalQSOptionValue + 1)

            # Cleanup for this test
            $db1, $db2 | Remove-DbaDatabase -ErrorAction SilentlyContinue
        }

        It "Apply to all databases except db4" {
            # Setup for this specific test
            $db1Name = "dbatoolsci_querystoretest1"
            $db1 = New-DbaDatabase -SqlInstance $server2 -Name $db1Name

            $db1QSOptions = Get-DbaDbQueryStoreOption -SqlInstance $server2 -Database $db1Name
            $originalQSOptionValue = $db1QSOptions.DataFlushIntervalInSeconds
            $updatedQSOption = $db1QSOptions.DataFlushIntervalInSeconds + 1
            $splatSetOptions = @{
                SqlInstance   = $server2
                Database      = $db1Name
                FlushInterval = $updatedQSOption
                State         = "ReadWrite"
            }
            $updatedDB1Options = Set-DbaDbQueryStoreOption @splatSetOptions

            $db2Name = "dbatoolsci_querystoretest2"
            $db2 = New-DbaDatabase -SqlInstance $server2 -Name $db2Name

            $db3Name = "dbatoolsci_querystoretest3"
            $db3 = New-DbaDatabase -SqlInstance $server2 -Name $db3Name

            $db4Name = "dbatoolsci_querystoretest4"
            $db4 = New-DbaDatabase -SqlInstance $server2 -Name $db4Name

            # Test assertions
            $db3QSOptions = Get-DbaDbQueryStoreOption -SqlInstance $server2 -Database $db3Name
            $db3QSOptions.DataFlushIntervalInSeconds | Should -Be $originalQSOptionValue

            $splatCopyExclude = @{
                Source         = $server2
                SourceDatabase = $db1Name
                Destination    = $server2
                Exclude        = $db4Name
            }
            $result = Copy-DbaDbQueryStoreOption @splatCopyExclude

            $result.Status | Should -Not -Contain "Failed"
            $result.Status | Should -Not -Contain "Skipped"

            $result.Name | Should -Contain $db1Name
            $result.Name | Should -Contain $db2Name
            $result.Name | Should -Contain $db3Name
            $result.Name | Should -Not -Contain $db4Name

            $result.SourceDatabaseID | Should -Contain $db1.ID

            $result.DestinationDatabaseID | Should -Contain $db1.ID
            $result.DestinationDatabaseID | Should -Contain $db2.ID
            $result.DestinationDatabaseID | Should -Contain $db3.ID

            $dbQSOptions = Get-DbaDbQueryStoreOption -SqlInstance $server2 -Database $db1Name, $db2Name, $db3Name
            ($dbQSOptions | Where-Object { $PSItem.DataFlushIntervalInSeconds -eq ($originalQSOptionValue + 1) }).Count | Should -Be 3

            $db4QSOptions = Get-DbaDbQueryStoreOption -SqlInstance $server2 -Database $db4Name
            $db4QSOptions.DataFlushIntervalInSeconds | Should -Be $originalQSOptionValue

            # Cleanup for this test
            $db1, $db2, $db3, $db4 | Remove-DbaDatabase -ErrorAction SilentlyContinue
        }
    }
}