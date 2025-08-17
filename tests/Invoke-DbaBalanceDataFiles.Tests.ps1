$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Parameter validation" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Table', 'RebuildOffline', 'EnableException', 'Force'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        # Create the server object
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2

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
        Remove-DbaDatabase -SqlInstance $server -Database $dbname -Confirm:$false
    }

    Context "Data is balanced among data files" {

        $results = Invoke-DbaBalanceDataFiles -SqlInstance $server -Database $dbname -RebuildOffline -Force

        It "Result returns success" {
            $results.Success | Should -Be $true
        }

        $sizeUsedBefore = $results.DataFilesStart[0].UsedSpace.Kilobyte
        $sizeUsedAfter = $results.DataFilesEnd[0].UsedSpace.Kilobyte

        It "New used space should be less" {

            $sizeUsedAfter | Should -BeLessThan $sizeUsedBefore
        }
    }
}