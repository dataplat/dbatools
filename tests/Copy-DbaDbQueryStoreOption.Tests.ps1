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
        BeforeEach {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $db1Name = "dbatoolsci_querystoretest1_$(Get-Random)"
            $db1 = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $db1Name

            $db2Name = "dbatoolsci_querystoretest2_$(Get-Random)"
            $db2 = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $db2Name

            $db3Name = "dbatoolsci_querystoretest3_$(Get-Random)"
            $db3 = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $db3Name

            $db4Name = "dbatoolsci_querystoretest4_$(Get-Random)"
            $db4 = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $db4Name

            $db1QSOptions = Get-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceSingle -Database $db1Name
            $originalQSOptionValue = $db1QSOptions.DataFlushIntervalInSeconds
            $updatedQSOptionValue = $db1QSOptions.DataFlushIntervalInSeconds + 1
            $splatSetOptions = @{
                SqlInstance   = $TestConfig.InstanceSingle
                Database      = $db1Name
                FlushInterval = $updatedQSOptionValue
                State         = "ReadWrite"
            }
            $null = Set-DbaDbQueryStoreOption @splatSetOptions

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterEach {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $db1Name, $db2Name, $db3Name, $db4Name

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Copy the query store options from one db to another on the same instance" {
            $splatCopyOptions = @{
                Source              = $TestConfig.InstanceSingle
                SourceDatabase      = $db1Name
                Destination         = $TestConfig.InstanceSingle
                DestinationDatabase = $db2Name
            }
            $result = Copy-DbaDbQueryStoreOption @splatCopyOptions

            $result.Status | Should -Be "Successful"
            $result.SourceDatabase | Should -Be $db1Name
            $result.SourceDatabaseID | Should -Be $db1.ID
            $result.Name | Should -Be $db2Name
            $result.DestinationDatabaseID | Should -Be $db2.ID

            $db2QSOptions = Get-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceSingle -Database $db2Name
            $db2QSOptions.DataFlushIntervalInSeconds | Should -Be $updatedQSOptionValue
        }

        It "Apply to all databases except db4" {
            $splatCopyExclude = @{
                Source         = $TestConfig.InstanceSingle
                SourceDatabase = $db1Name
                Destination    = $TestConfig.InstanceSingle
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

            $dbQSOptions = Get-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceSingle -Database $db1Name, $db2Name, $db3Name
            ($dbQSOptions | Where-Object { $PSItem.DataFlushIntervalInSeconds -eq ($originalQSOptionValue + 1) }).Count | Should -Be 3

            $db4QSOptions = Get-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceSingle -Database $db4Name
            $db4QSOptions.DataFlushIntervalInSeconds | Should -Be $originalQSOptionValue
        }

        It "Returns output with the expected TypeName" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "dbatools.MigrationObject"
        }

        It "Has the expected default display properties" {
            $result | Should -Not -BeNullOrEmpty
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}