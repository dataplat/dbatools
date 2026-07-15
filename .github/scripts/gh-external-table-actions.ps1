[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "", Justification = "The credential is an ephemeral, fixed CI-only SQL login for isolated containers.")]
param()

Describe "Copy-DbaDbTableData external table integration" -Tag "IntegrationTests", "ExternalTable", "S3" {
    BeforeAll {
        $password = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "sa", $password

        if (-not (Get-Module dbatools)) {
            Import-Module dbatools.library
            try {
                Import-Module dbatools -ErrorAction Stop
            } catch {
                Write-Warning "Importing dbatools from source"
                Import-Module ./dbatools.psd1 -Force
            }
        }

        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $PSDefaultParameterValues["*-Dba*:Confirm"] = $false

        $script:sourceDatabaseName = "dbatoolsci_external_source"
        $script:destinationDatabaseName = "dbatoolsci_external_destination"
        $script:server = Connect-DbaInstance -SqlInstance localhost -SqlCredential $cred

        $null = $script:server.Query("
            EXEC sp_configure 'polybase enabled', 1;
            RECONFIGURE;
        ")
        $polyBaseConfiguration = $script:server.Query("
            SELECT CAST(value_in_use AS INT) AS ValueInUse
            FROM sys.configurations
            WHERE name = 'polybase enabled';
        ")
        if ($polyBaseConfiguration.ValueInUse -ne 1) {
            throw "SQL Server did not enable the polybase engine configuration required for external tables."
        }

        $null = New-DbaDatabase -SqlInstance $script:server -Name $script:sourceDatabaseName
        $null = New-DbaDatabase -SqlInstance $script:server -Name $script:destinationDatabaseName

        $script:sourceDatabase = Get-DbaDatabase -SqlInstance $script:server -Database $script:sourceDatabaseName
        $script:destinationDatabase = Get-DbaDatabase -SqlInstance $script:server -Database $script:destinationDatabaseName

        $null = $script:sourceDatabase.Query("
            CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'dbatools.IO';

            CREATE DATABASE SCOPED CREDENTIAL DbatoolsS3Credential
            WITH IDENTITY = 'S3 Access Key',
                 SECRET = 'minioadmin:minioadmin';

            CREATE EXTERNAL DATA SOURCE DbatoolsS3Source
            WITH
            (
                LOCATION = 's3://minio:9000/',
                CREDENTIAL = DbatoolsS3Credential
            );

            CREATE EXTERNAL FILE FORMAT DbatoolsDelimitedText
            WITH
            (
                FORMAT_TYPE = DELIMITEDTEXT,
                FORMAT_OPTIONS
                (
                    FIELD_TERMINATOR = '|',
                    FIRST_ROW = 1,
                    USE_TYPE_DEFAULT = TRUE
                )
            );

            CREATE EXTERNAL TABLE dbo.ExternalOrders
            (
                OrderId INT NOT NULL,
                Description VARCHAR(200) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,
                Amount DECIMAL(18, 4) NOT NULL
            )
            WITH
            (
                LOCATION = '/sqlbackups/external/orders.csv',
                DATA_SOURCE = DbatoolsS3Source,
                FILE_FORMAT = DbatoolsDelimitedText
            );
        ")

        $null = $script:destinationDatabase.Query("CREATE SCHEMA archive;")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if ($script:server) {
            $null = Remove-DbaDatabase -SqlInstance $script:server -Database $script:sourceDatabaseName, $script:destinationDatabaseName
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        $PSDefaultParameterValues.Remove("*-Dba*:Confirm")
    }

    It "auto-creates an ordinary table and copies rows from real S3 external data" {
        $externalTable = Get-DbaDbTable -SqlInstance $script:server -Database $script:sourceDatabaseName -Table "dbo.ExternalOrders"
        $externalTable.IsExternal | Should -BeTrue

        $sourceRows = $script:sourceDatabase.Query("SELECT OrderId, Description, Amount FROM dbo.ExternalOrders ORDER BY OrderId;")
        $sourceRows.Count | Should -Be 2

        $splatCopy = @{
            SqlInstance              = "localhost"
            SqlCredential            = $cred
            Database                 = $script:sourceDatabaseName
            Table                    = "dbo.ExternalOrders"
            Destination              = "localhost"
            DestinationSqlCredential = $cred
            DestinationDatabase      = $script:destinationDatabaseName
            DestinationTable         = "[archive].[OrdersCopy]"
            AutoCreateTable          = $true
            Confirm                  = $false
            EnableException          = $true
        }
        $result = Copy-DbaDbTableData @splatCopy

        $result.RowsCopied | Should -Be 2
        $result.DestinationSchema | Should -Be "archive"
        $result.DestinationTable | Should -Be "OrdersCopy"

        $destinationTable = Get-DbaDbTable -SqlInstance $script:server -Database $script:destinationDatabaseName -Table "archive.OrdersCopy"
        $destinationTable.IsExternal | Should -BeFalse
        $destinationTable.Columns["OrderId"].DataType.Name | Should -Be "int"
        $destinationTable.Columns["OrderId"].Nullable | Should -BeFalse
        $destinationTable.Columns["Description"].DataType.Name | Should -Be "varchar"
        $destinationTable.Columns["Description"].DataType.MaximumLength | Should -Be 200
        $destinationTable.Columns["Description"].Collation | Should -Be "Latin1_General_100_CI_AS_SC_UTF8"
        $destinationTable.Columns["Description"].Nullable | Should -BeTrue
        $destinationTable.Columns["Amount"].DataType.NumericPrecision | Should -Be 18
        $destinationTable.Columns["Amount"].DataType.NumericScale | Should -Be 4
        $destinationTable.Columns["Amount"].Nullable | Should -BeFalse

        $destinationRows = $script:destinationDatabase.Query("SELECT OrderId, Description, Amount FROM archive.OrdersCopy ORDER BY OrderId;")
        $destinationRows.Count | Should -Be 2
        $destinationRows[0].OrderId | Should -Be 1
        $destinationRows[0].Description | Should -Be "First order"
        $destinationRows[0].Amount | Should -Be 12.3400
        $destinationRows[1].OrderId | Should -Be 2
        $destinationRows[1].Description | Should -Be "Second order"
        $destinationRows[1].Amount | Should -Be 56.7800
    }
}
