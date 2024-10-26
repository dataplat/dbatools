#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan

Describe "Copy-DbaDbQueryStoreOption" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Copy-DbaDbQueryStoreOption
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "Source",
                "SourceSqlCredential", 
                "SourceDatabase",
                "Destination",
                "DestinationSqlCredential",
                "DestinationDatabase",
                "Exclude",
                "AllDatabases",
                "EnableException",
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasParams = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasParams | Should -BeNullOrEmpty
        }
    }
}

Describe "Copy-DbaDbQueryStoreOption" -Tag "IntegrationTests" {
    Context "Verifying query store options are copied" {
        BeforeAll {
            $server2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        }

        BeforeEach {
            $db1Name = "dbatoolsci_querystoretest1"
            $db1 = New-DbaDatabase -SqlInstance $server2 -Name $db1Name

            $db1QSOptions = Get-DbaDbQueryStoreOption -SqlInstance $server2 -Database $db1Name
            $originalQSOptionValue = $db1QSOptions.DataFlushIntervalInSeconds
            $updatedQSOption = $db1QSOptions.DataFlushIntervalInSeconds + 1
            $updatedDB1Options = Set-DbaDbQueryStoreOption -SqlInstance $server2 -Database $db1Name -FlushInterval $updatedQSOption -State ReadWrite

            $db2Name = "dbatoolsci_querystoretest2"
            $db2 = New-DbaDatabase -SqlInstance $server2 -Name $db2Name

            $db3Name = "dbatoolsci_querystoretest3"
            $db3 = New-DbaDatabase -SqlInstance $server2 -Name $db3Name

            $db4Name = "dbatoolsci_querystoretest4"
            $db4 = New-DbaDatabase -SqlInstance $server2 -Name $db4Name
        }

        AfterEach {
            $db1, $db2, $db3, $db4 | Remove-DbaDatabase -Confirm:$false
        }

        It "Copy the query store options from one db to another on the same instance" {
            $db2QSOptions = Get-DbaDbQueryStoreOption -SqlInstance $server2 -Database $db2Name
            $db2QSOptions.DataFlushIntervalInSeconds | Should -Be $originalQSOptionValue

            $result = Copy-DbaDbQueryStoreOption -Source $server2 -SourceDatabase $db1Name -Destination $server2 -DestinationDatabase $db2Name

            $result.Status | Should -Be "Successful"
            $result.SourceDatabase | Should -Be $db1Name
            $result.SourceDatabaseID | Should -Be $db1.ID
            $result.Name | Should -Be $db2Name
            $result.DestinationDatabaseID | Should -Be $db2.ID

            $db2QSOptions = Get-DbaDbQueryStoreOption -SqlInstance $server2 -Database $db2Name
            $db2QSOptions.DataFlushIntervalInSeconds | Should -Be ($originalQSOptionValue + 1)
        }

        It "Apply to all databases except db4" {
            $db3QSOptions = Get-DbaDbQueryStoreOption -SqlInstance $server2 -Database $db3Name
            $db3QSOptions.DataFlushIntervalInSeconds | Should -Be $originalQSOptionValue

            $result = Copy-DbaDbQueryStoreOption -Source $server2 -SourceDatabase $db1Name -Destination $server2 -Exclude $db4Name

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
        }
    }
}
