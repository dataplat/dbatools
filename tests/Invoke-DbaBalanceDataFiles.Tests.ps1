#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaBalanceDataFiles",
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
                "Table",
                "RebuildOffline",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # Create the server object
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        # Get the default data directory to create the additional data file
        $defaultdata = (Get-DbaDefaultPath -SqlInstance $server).Data

        # Set the database name
        $dbname = "dbatoolscsi_balance"

        # Create the database
        $server.Query("CREATE DATABASE [$dbname]")

        # Refresh the database to get all the latest changes
        $server.Databases.Refresh()

        # retrieve the database object for later
        $db = Get-DbaDatabase -SqlInstance $server -Database $dbname

        # Create the tables
        $db.Query("CREATE TABLE table1 (ID1 INT IDENTITY PRIMARY KEY, Name1 char(100))")
        $db.Query("CREATE TABLE table2 (ID1 INT IDENTITY PRIMARY KEY, Name2 char(100))")

        # Generate the values
        $sqlvalues = New-Object System.Collections.ArrayList
        1 .. 1000 | ForEach-Object { $null = $sqlvalues.Add("('some value')") }

        $db.Query("insert into table1 (Name1) Values $($sqlvalues -join ',')")
        $db.Query("insert into table1 (Name1) Values $($sqlvalues -join ',')")
        $db.Query("insert into table1 (Name1) Values $($sqlvalues -join ',')")
        $db.Query("insert into table1 (Name1) Values $($sqlvalues -join ',')")
        $db.Query("insert into table1 (Name1) Values $($sqlvalues -join ',')")
        $db.Query("insert into table2 (Name2) Values $($sqlvalues -join ',')")
        $db.Query("insert into table2 (Name2) Values $($sqlvalues -join ',')")
        $db.Query("insert into table2 (Name2) Values $($sqlvalues -join ',')")
        $db.Query("insert into table2 (Name2) Values $($sqlvalues -join ',')")
        $db.Query("insert into table2 (Name2) Values $($sqlvalues -join ',')")

        $db.Query("ALTER DATABASE $dbname ADD FILE (NAME = secondfile, FILENAME = '$defaultdata\$dbname-secondaryfg.ndf') TO FILEGROUP [PRIMARY]")

    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $server -Database $dbname
    }

    Context "Data is balanced among data files" {
        BeforeAll {
            $results = Invoke-DbaBalanceDataFiles -SqlInstance $server -Database $dbname -RebuildOffline -Force
        }

        It "Result returns success" {
            $results.Success | Should -BeTrue
        }

        It "New used space should be less" {
            $sizeUsedBefore = $results.DataFilesStart[0].UsedSpace.Kilobyte
            $sizeUsedAfter = $results.DataFilesEnd[0].UsedSpace.Kilobyte

            $sizeUsedAfter | Should -BeLessThan $sizeUsedBefore
        }
    }

    Context "Output validation" {
        BeforeAll {
            $resultOutput = Invoke-DbaBalanceDataFiles -SqlInstance $server -Database $dbname -RebuildOffline -Force
        }

        It "Returns output that is not null" {
            $resultOutput | Should -Not -BeNullOrEmpty
        }

        It "Has the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Start",
                "End",
                "Elapsed",
                "Success",
                "Unsuccessful",
                "DataFilesStart",
                "DataFilesEnd"
            )
            foreach ($prop in $expectedProperties) {
                $resultOutput[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }

        It "Has ComputerName populated" {
            $resultOutput[0].ComputerName | Should -Not -BeNullOrEmpty
        }

        It "Has SqlInstance populated" {
            $resultOutput[0].SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "Has DataFilesStart as an array with file details" {
            $resultOutput[0].DataFilesStart | Should -Not -BeNullOrEmpty
            $resultOutput[0].DataFilesStart[0].psobject.Properties.Name | Should -Contain "LogicalName"
            $resultOutput[0].DataFilesStart[0].psobject.Properties.Name | Should -Contain "PhysicalName"
            $resultOutput[0].DataFilesStart[0].psobject.Properties.Name | Should -Contain "Size"
            $resultOutput[0].DataFilesStart[0].psobject.Properties.Name | Should -Contain "UsedSpace"
        }

        It "Has DataFilesEnd as an array with file details" {
            $resultOutput[0].DataFilesEnd | Should -Not -BeNullOrEmpty
            $resultOutput[0].DataFilesEnd[0].psobject.Properties.Name | Should -Contain "LogicalName"
            $resultOutput[0].DataFilesEnd[0].psobject.Properties.Name | Should -Contain "PhysicalName"
            $resultOutput[0].DataFilesEnd[0].psobject.Properties.Name | Should -Contain "Size"
            $resultOutput[0].DataFilesEnd[0].psobject.Properties.Name | Should -Contain "UsedSpace"
        }
    }
}