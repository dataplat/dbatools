$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys
        [object[]]$knownParameters = @(
            'SqlInstance',
            'SqlCredential',
            'Destination',
            'DestinationSqlCredential',
            'Database',
            'DestinationDatabase',
            'BatchSize',
            'BulkCopyTimeOut',
            'InputObject',
            'EnableException',
            'CopyAllObjects',
            'CopyAll',
            'SchemaOnly',
            'DataOnly'
        )
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            $knownParameters | Where-Object {$_} | Should -BeIn $params
            $params | Should -BeIn ($knownParameters | Where-Object {$_})
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database tempdb
        $db2 = Get-DbaDatabase -SqlInstance $script:instance2 -Database tempdb
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
    }
    Context "Testing connection parameters" {
        It "Should create a transfer object" {
            $transfer = New-DbaDbTransfer -SqlInstance $script:instance1 -Database tempdb
            $transfer | Should -BeOfType Microsoft.SqlServer.Management.Smo.Transfer
            $transfer.BatchSize | Should -Be 50000
            $transfer.BulkCopyTimeout | Should -Be 5000
            $transfer.Database.Name | Should -Be tempdb
            $transfer.ObjectList | Should -BeNullOrEmpty
            $transfer.CopyAllObjects | Should -Be $false
            $allowedObjects | Foreach-Object { $transfer.$_ | Should -BeNullOrEmpty }
            $transfer.CopyData | Should -Be $true
            $transfer.CopySchema | Should -Be $true
            $transfer.DestinationDatabase | Should -Be tempdb
            $transfer.DestinationServer | Should -BeNullOrEmpty
        }
        It "Should properly assign dest server parameters from full connstring" {
            $transfer = New-DbaDbTransfer -SqlInstance $script:instance1 -Database tempdb -Destination 'Data Source=foo;User=bar;password=foobar;Initial Catalog=hog'
            $transfer.DestinationDatabase | Should -Be hog
            $transfer.DestinationLoginSecure | Should -Be $false
            $transfer.DestinationLogin | Should -Be bar
            $transfer.DestinationPassword | Should -Be foobar
            $transfer.DestinationServer | Should -Be foo
        }
        It "Should properly assign dest server parameters from trusted connstring" {
            $transfer = New-DbaDbTransfer -SqlInstance $script:instance1 -Database tempdb -Destination 'Data Source=foo;Integrated Security=True'
            $transfer.DestinationDatabase | Should -Be tempdb
            $transfer.DestinationLoginSecure | Should -Be $true
            $transfer.DestinationLogin | Should -BeNullOrEmpty
            $transfer.DestinationPassword | Should -BeNullOrEmpty
            $transfer.DestinationServer | Should -Be foo
        }
        It "Should properly assign dest server parameters from server object" {
            $dest = Connect-DbaInstance -SqlInstance $script:instance2 -Database msdb
            $connStringBuilder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $dest.ConnectionContext.ConnectionString
            $transfer = New-DbaDbTransfer -SqlInstance $script:instance1 -Database tempdb -Destination $dest
            $transfer.DestinationDatabase | Should -Be $connStringBuilder['Initial Catalog']
            $transfer.DestinationLoginSecure | Should -Be $connStringBuilder['Integrated Security']
            $transfer.DestinationLogin | Should -Be $connStringBuilder['User ID']
            $transfer.DestinationPassword | Should -Be $connStringBuilder['Password']
            $transfer.DestinationServer | Should -Be $connStringBuilder['Data Source']
        }
        It "Should properly assign dest server parameters from plaintext params" {
            $transfer = New-DbaDbTransfer -SqlInstance $script:instance1 -Database tempdb -Destination foo -DestinationDatabase bar -DestinationSqlCredential $creds
            $transfer.DestinationDatabase | Should -Be bar
            $transfer.DestinationLoginSecure | Should -Be $false
            $transfer.DestinationLogin | Should -Be $creds.UserName
            $transfer.DestinationPassword | Should -Be $creds.GetNetworkCredential().Password
            $transfer.DestinationServer | Should -Be foo
        }
    }
    Context "Testing transfer parameters" {
        It "Should script all objects" {
            $transfer = New-DbaDbTransfer -SqlInstance $script:instance1 -Database tempdb -CopyAllObjects
            $transfer.CopyData | Should -Be $true
            $transfer.CopySchema | Should -Be $true
            $script = $transfer.ScriptTransfer() -join "`n"
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test2`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test3`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test4`]*'
        }
        It "Should script all tables with just schemas" {
            $transfer = New-DbaDbTransfer -SqlInstance $script:instance1 -Database tempdb -CopyAll Tables -SchemaOnly
            $transfer.CopyData | Should -Be $false
            $transfer.CopySchema | Should -Be $true
            $script = $transfer.ScriptTransfer() -join "`n"
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test2`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test3`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test4`]*'
        }
        It "Should script one table with just data" {
            $table = Get-DbaDbTable -SqlInstance $script:instance1 -Database tempdb -Table transfer_test
            $transfer = New-DbaDbTransfer -SqlInstance $script:instance1 -Database tempdb -InputObject $table -DataOnly
            $transfer.ObjectList.Count | Should -Be 1
            $transfer.CopyData | Should -Be $true
            $transfer.CopySchema | Should -Be $false
            $transfer = New-DbaDbTransfer -SqlInstance $script:instance1 -Database tempdb -InputObject $table
            # # data only ScriptTransfer still creates schema
            $script = $transfer.ScriptTransfer() -join "`n"
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
        }
        It "Should script two tables from pipeline" {
            $tables = Get-DbaDbTable -SqlInstance $script:instance1 -Database tempdb -Table transfer_test2, transfer_test4
            $transfer = $tables | New-DbaDbTransfer -SqlInstance $script:instance1 -Database tempdb
            $transfer.ObjectList.Count | Should -Be 2
            $script = $transfer.ScriptTransfer() -join "`n"
            $script | Should -Not -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test2`]*'
            $script | Should -Not -BeLike '*CREATE TABLE `[dbo`].`[transfer_test3`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test4`]*'
        }
    }
}