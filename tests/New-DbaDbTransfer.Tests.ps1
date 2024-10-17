param($ModuleName = 'dbatools')

Describe "New-DbaDbTransfer" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $dbName = 'dbatools_transfer'
        $source = Connect-DbaInstance -SqlInstance $script:instance1
        $destination = Connect-DbaInstance -SqlInstance $script:instance2
        $source.Query("CREATE DATABASE $dbName")
        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbName
        $null = $db.Query("CREATE TABLE dbo.transfer_test (id int);
            INSERT dbo.transfer_test
            SELECT top 10 1
            FROM sys.objects")
        $null = $db.Query("CREATE TABLE dbo.transfer_test2 (id int)")
        $null = $db.Query("CREATE TABLE dbo.transfer_test3 (id int)")
        $null = $db.Query("CREATE TABLE dbo.transfer_test4 (id int);
            INSERT dbo.transfer_test4
            SELECT top 13 1
            FROM sys.objects")

        $allowedObjects = @(
            'FullTextCatalogs',
            'FullTextStopLists',
            'SearchPropertyLists',
            'Tables',
            'Views',
            'StoredProcedures',
            'UserDefinedFunctions',
            'UserDefinedDataTypes',
            'UserDefinedTableTypes',
            'PlanGuides',
            'Rules',
            'Defaults',
            'Users',
            'Roles',
            'PartitionSchemes',
            'PartitionFunctions',
            'XmlSchemaCollections',
            'SqlAssemblies',
            'UserDefinedAggregates',
            'UserDefinedTypes',
            'Schemas',
            'Synonyms',
            'Sequences',
            'DatabaseTriggers',
            'DatabaseScopedCredentials',
            'ExternalFileFormats',
            'ExternalDataSources',
            'Logins',
            'ExternalLibraries'
        )
        $securePassword = 'bar' | ConvertTo-SecureString -AsPlainText -Force
        $creds = New-Object PSCredential ('foo', $securePassword)
    }

    AfterAll {
        try {
            $null = $db.Query("DROP TABLE dbo.transfer_test")
            $null = $db.Query("DROP TABLE dbo.transfer_test2")
            $null = $db.Query("DROP TABLE dbo.transfer_test3")
            $null = $db.Query("DROP TABLE dbo.transfer_test4")
        } catch {
            $null = 1
        }
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbName -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDbTransfer
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have DestinationSqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlInstance -Type DbaInstanceParameter
        }
        It "Should have DestinationSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String
        }
        It "Should have DestinationDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationDatabase -Type String
        }
        It "Should have BatchSize as a parameter" {
            $CommandUnderTest | Should -HaveParameter BatchSize -Type Int32
        }
        It "Should have BulkCopyTimeOut as a parameter" {
            $CommandUnderTest | Should -HaveParameter BulkCopyTimeOut -Type Int32
        }
        It "Should have ScriptingOption as a parameter" {
            $CommandUnderTest | Should -HaveParameter ScriptingOption -Type ScriptingOptions
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type NamedSmoObject[]
        }
        It "Should have CopyAllObjects as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter CopyAllObjects -Type SwitchParameter
        }
        It "Should have CopyAll as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyAll -Type String[]
        }
        It "Should have SchemaOnly as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter SchemaOnly -Type SwitchParameter
        }
        It "Should have DataOnly as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DataOnly -Type SwitchParameter
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Testing connection parameters" {
        It "Should create a transfer object" {
            $transfer = New-DbaDbTransfer -SqlInstance $script:instance1 -Database $dbName
            $transfer | Should -BeOfType Microsoft.SqlServer.Management.Smo.Transfer
            $transfer.BatchSize | Should -Be 50000
            $transfer.BulkCopyTimeout | Should -Be 5000
            $transfer.Database.Name | Should -Be $dbName
            $transfer.ObjectList | Should -BeNullOrEmpty
            $transfer.CopyAllObjects | Should -BeFalse
            $allowedObjects | ForEach-Object { $transfer.$_ | Should -BeNullOrEmpty }
            $transfer.CopyData | Should -BeTrue
            $transfer.CopySchema | Should -BeTrue
            $transfer.DestinationDatabase | Should -Be $dbName
            $transfer.DestinationServer | Should -BeNullOrEmpty
        }

        It "Should properly assign dest server parameters from full connstring" {
            $transfer = New-DbaDbTransfer -SqlInstance $script:instance1 -Database $dbName -DestinationSqlInstance 'Data Source=foo;User=bar;password=foobar;Initial Catalog=hog'
            $transfer.DestinationDatabase | Should -Be 'hog'
            $transfer.DestinationLoginSecure | Should -BeFalse
            $transfer.DestinationLogin | Should -Be 'bar'
            $transfer.DestinationPassword | Should -Be 'foobar'
            $transfer.DestinationServer | Should -Be 'foo'
        }

        It "Should properly assign dest server parameters from trusted connstring" {
            $transfer = New-DbaDbTransfer -SqlInstance $script:instance1 -Database $dbName -DestinationSqlInstance 'Data Source=foo;Integrated Security=True'
            $transfer.DestinationDatabase | Should -Be $dbName
            $transfer.DestinationLoginSecure | Should -BeTrue
            $transfer.DestinationLogin | Should -BeNullOrEmpty
            $transfer.DestinationPassword | Should -BeNullOrEmpty
            $transfer.DestinationServer | Should -Be 'foo'
        }

        It "Should properly assign dest server parameters from server object" {
            $dest = Connect-DbaInstance -SqlInstance $script:instance2 -Database msdb
            $connStringBuilder = New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder $dest.ConnectionContext.ConnectionString
            $transfer = New-DbaDbTransfer -SqlInstance $script:instance1 -Database $dbName -DestinationSqlInstance $dest
            $transfer.DestinationDatabase | Should -Be $connStringBuilder['Initial Catalog']
            $transfer.DestinationLoginSecure | Should -Be $connStringBuilder['Integrated Security']
            $transfer.DestinationLogin | Should -Be $connStringBuilder['User ID']
            $transfer.DestinationPassword | Should -Be $connStringBuilder['Password']
            $transfer.DestinationServer | Should -Be $connStringBuilder['Data Source']
        }

        It "Should properly assign dest server parameters from plaintext params" {
            $transfer = New-DbaDbTransfer -SqlInstance $script:instance1 -Database $dbName -DestinationSqlInstance foo -DestinationDatabase bar -DestinationSqlCredential $creds
            $transfer.DestinationDatabase | Should -Be 'bar'
            $transfer.DestinationLoginSecure | Should -BeFalse
            $transfer.DestinationLogin | Should -Be $creds.UserName
            $transfer.DestinationPassword | Should -Be $creds.GetNetworkCredential().Password
            $transfer.DestinationServer | Should -Be 'foo'
        }
    }

    Context "Testing function parameters" {
        It "Should script all objects" {
            $transfer = New-DbaDbTransfer -SqlInstance $script:instance1 -Database $dbName -CopyAllObjects
            $transfer.CopyData | Should -BeTrue
            $transfer.CopySchema | Should -BeTrue
            $script = $transfer.ScriptTransfer() -join "`n"
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test2`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test3`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test4`]*'
        }

        It "Should script all tables with just schemas" {
            $transfer = New-DbaDbTransfer -SqlInstance $script:instance1 -Database $dbName -CopyAll Tables -SchemaOnly
            $transfer.CopyData | Should -BeFalse
            $transfer.CopySchema | Should -BeTrue
            $script = $transfer.ScriptTransfer() -join "`n"
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test2`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test3`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test4`]*'
        }

        It "Should script one table with just data" {
            $table = Get-DbaDbTable -SqlInstance $script:instance1 -Database $dbName -Table transfer_test
            $transfer = New-DbaDbTransfer -SqlInstance $script:instance1 -Database $dbName -InputObject $table -DataOnly
            $transfer.ObjectList.Count | Should -Be 1
            $transfer.CopyData | Should -BeTrue
            $transfer.CopySchema | Should -BeFalse
            $script = $transfer.ScriptTransfer() -join "`n"
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
        }

        It "Should script two tables from pipeline" {
            $tables = Get-DbaDbTable -SqlInstance $script:instance1 -Database $dbName -Table transfer_test2, transfer_test4
            $transfer = $tables | New-DbaDbTransfer -SqlInstance $script:instance1 -Database $dbName
            $transfer.ObjectList.Count | Should -Be 2
            $script = $transfer.ScriptTransfer() -join "`n"
            $script | Should -Not -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test2`]*'
            $script | Should -Not -BeLike '*CREATE TABLE `[dbo`].`[transfer_test3`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test4`]*'
        }

        It "Should accept script options object" {
            $options = New-DbaScriptingOption
            $options.ScriptDrops = $true
            $transfer = New-DbaDbTransfer -SqlInstance $script:instance1 -Database $dbName -CopyAll Tables -ScriptingOption $options
            $transfer.Options.ScriptDrops | Should -BeTrue
            $script = $transfer.ScriptTransfer() -join "`n"
            $script | Should -BeLike '*DROP TABLE `[dbo`].`[transfer_test`]*'
        }
    }

    Context "Testing object transfer" {
        BeforeEach {
            $destination.Query("CREATE DATABASE $dbname")
            $db2 = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbName
        }

        AfterEach {
            Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbName -Confirm:$false
        }

        It "Should transfer all tables" {
            $transfer = New-DbaDbTransfer -SqlInstance $script:instance1 -DestinationSqlInstance $script:instance2 -Database $dbName -CopyAll Tables
            $transfer.TransferData()
            $tables = Get-DbaDbTable -SqlInstance $script:instance2 -Database $dbName -Table transfer_test, transfer_test2, transfer_test3, transfer_test4
            $tables.Count | Should -Be 4
            $db.Query("select id from dbo.transfer_test").id | Should -Not -BeNullOrEmpty
            $db.Query("select id from dbo.transfer_test4").id | Should -Not -BeNullOrEmpty
            $db.Query("select id from dbo.transfer_test").id | Should -BeIn $db2.Query("select id from dbo.transfer_test").id
            $db.Query("select id from dbo.transfer_test4").id | Should -BeIn $db2.Query("select id from dbo.transfer_test4").id
        }

        It "Should transfer two tables with just schemas" {
            $sourceTables = Get-DbaDbTable -SqlInstance $script:instance1 -Database $dbName -Table transfer_test, transfer_test2
            $transfer = $sourceTables | New-DbaDbTransfer -SqlInstance $script:instance1 -DestinationSqlInstance $script:instance2 -Database $dbName -SchemaOnly
            $transfer.TransferData()
            $tables = Get-DbaDbTable -SqlInstance $script:instance2 -Database $dbName -Table transfer_test, transfer_test2
            $tables.Count | Should -Be 2
            $db2.Query("select id from dbo.transfer_test").id | Should -BeNullOrEmpty
        }

        It "Should transfer two tables without copying schema" {
            $null = $db2.Query("CREATE TABLE dbo.transfer_test (id int)")
            $null = $db2.Query("CREATE TABLE dbo.transfer_test2 (id int)")
            $sourceTables = Get-DbaDbTable -SqlInstance $script:instance1 -Database $dbName -Table transfer_test, transfer_test2
            $transfer = $sourceTables | New-DbaDbTransfer -SqlInstance $script:instance1 -DestinationSqlInstance $script:instance2 -Database $dbName -DataOnly
            $transfer.TransferData()
            $tables = Get-DbaDbTable -SqlInstance $script:instance2 -Database $dbName -Table transfer_test, transfer_test2
            $tables.Count | Should -Be 2
            $db.Query("select id from dbo.transfer_test").id | Should -Not -BeNullOrEmpty
            $db.Query("select id from dbo.transfer_test").id | Should -BeIn $db2.Query("select id from dbo.transfer_test").id
        }
    }
}
