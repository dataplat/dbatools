$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = @('SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'SchemaName', 'SchemaNameMatchType', 
                                        'TableName', 'TableNameMatchType', 'IndexName', 'IndexNameMatchType', 'IndexColumnName', 
                                        'IndexColumnNameMatchType', 'IncludeSystemDatabases', 'IncludeStats', 'IncludeDataTypes', 
                                        'Raw', 'IncludeFragmentation', 'EnableException')
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}



Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Command finds indexes using all parameters" {
        
        BeforeAll {
            $testInstance = $script:dbatoolsci_computer
            $testDatabase = 'dbatoolsci_findidxtestdb'
            $testSchema = 'dbatoolsTestSchema'
            $testTable = 'dbatoolsTestObjects'
            $testIndexName = 'ix_dbatoolsTestObjects_name'
            $testIndexObjecdtId = 'ix_dbatoolsTestObjects_object_id'
            $testPartialNameAndCaseSen = 'dbaTOOLS'
        
            #Create a test database with a test schema and a table with two indexes
            $null = New-DbaDatabase -SqlInstance $testInstance -Name $testDatabase
            $null = Invoke-DbaQuery -SqlInstance $testInstance -Database $testDatabase -Query "CREATE SCHEMA $testSchema;"
            $null = Invoke-DbaQuery -SqlInstance $testInstance -Database $testDatabase -Query "SELECT * INTO $testSchema.$testTable FROM master.sys.objects;"
            $null = Invoke-DbaQuery -SqlInstance $testInstance -Database $testDatabase -Query "CREATE NONCLUSTERED INDEX $testIndexName ON $testSchema.$testTable (name);"
            $null = Invoke-DbaQuery -SqlInstance $testInstance -Database $testDatabase -Query "CREATE NONCLUSTERED INDEX $testIndexObjecdtId ON $testSchema.$testTable (object_id);"        
        }
        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $testInstance -Database $testDatabase -Confirm: $false
        }
        
        #Find all indexes in Instance across DB's for our table and its indexes 
        # (may take a while to run if there are a ton of databases on the test instance)
        $params = @{
                    SqlInstance = $testInstance;
                    TableName = $testTable;
                }
        $results = Find-DbaDbIndex @params
        It "Should find 2 indexes across all DBs on Instance" {
            $results.Count | Should Be 2
        }
        
        #Find all indexes in our DB
        $params = @{
                    SqlInstance = $testInstance;
                    Database = $testDatabase;
                }
        $results = Find-DbaDbIndex @params
        It "Should find 2 indexes at DB level" {
            $results.Count | Should Be 2
        }

        #Find all indexes in non-existant schema
        $params = @{
                    SqlInstance = $testInstance;
                    Database = $testDatabase;
                    SchemaName = 'Non-existant';
                }
        $results = Find-DbaDbIndex @params
        It "Should find 0 indexes (non-existant schema)" {
            $results.Count | Should Be 0
        }

        #Find all indexes in our schema
        $params = @{
                    SqlInstance = $testInstance;
                    Database = $testDatabase;
                    SchemaName = $testSchema;
                }
        $results = Find-DbaDbIndex @params
        It "Should find 2 indexes (specific schema)" {
            $results.Count | Should Be 2
        }

        #Find all indexes in non-existant table        
        $params = @{
                    SqlInstance = $testInstance;
                    Database = $testDatabase;
                    SchemaName = $testSchema;
                    TableName = 'Non-existant';
                }
        $results = Find-DbaDbIndex @params
        It "Should find 0 indexes  (non-existant table)" {
            $results.Count | Should Be 0
        }

        #Find all indexes in our table
        $params = @{
                    SqlInstance = $testInstance;
                    Database = $testDatabase;
                    SchemaName = $testSchema;
                    TableName = $testTable;
                }
        $results = Find-DbaDbIndex @params
        It "Should find 2 indexes (specific table)" {
            $results.Count | Should Be 2
        }

        #Find all indexes by non-existant IndexName        
        $params = @{
                    SqlInstance = $testInstance;
                    Database = $testDatabase;
                    SchemaName = $testSchema;
                    TableName = $testTable;
                    IndexName = 'Non-existant';
                }
        $results = Find-DbaDbIndex @params
        It "Should find 0 indexes  (non-existant index)" {
            $results.Count | Should Be 0
        }

        #Find our index by our IndexName
        $params = @{
                    SqlInstance = $testInstance;
                    Database = $testDatabase;
                    SchemaName = $testSchema;
                    TableName = $testTable;
                    IndexName = $testIndexName;
                }
        $results = Find-DbaDbIndex @params
        It "Should find 1 indexes (specific index)" {
            $results.Count | Should Be 1
        }

        #Find our index using non-existant column
        $params = @{
                    SqlInstance = $testInstance;
                    Database = $testDatabase;
                    SchemaName = $testSchema;
                    TableName = $testTable;
                    IndexName = $testIndexName;
                    IndexColumnName = 'Non-existant';
                }
        $results = Find-DbaDbIndex @params
        It "Should find 0 indexes (non-existant column)" {
            $results.Count | Should Be 0
        }

        #Find our index using LIKE search on SchemaName
        $params = @{
                    SqlInstance = $testInstance;
                    Database = $testDatabase;
                    SchemaName = $testPartialNameAndCaseSen;
                    SchemaNameMatchType = 'Like';
                }
        $results = Find-DbaDbIndex @params
        It "Should find 2 indexes (LIKE search on SchemaName)" {
            $results.Count | Should Be 2
        }

        #Find our index using LIKE search on TableName
        $params = @{
                    SqlInstance = $testInstance;
                    Database = $testDatabase;
                    TableName = $testPartialNameAndCaseSen;
                    TableNameMatchType = 'Like';
                }
        $results = Find-DbaDbIndex @params
        It "Should find 2 indexes (LIKE search on TableName)" {
            $results.Count | Should Be 2
        }

        #Find our index using LIKE search on IndexName
        $params = @{
                    SqlInstance = $testInstance;
                    Database = $testDatabase;
                    IndexName = $testPartialNameAndCaseSen;
                    IndexNameMatchType = 'Like';
                }
        $results = Find-DbaDbIndex @params
        It "Should find 2 indexes (LIKE search on IndexName)" {
            $results.Count | Should Be 2
        }
        
        #Find our index using LIKE search on ColumnName (object_id column)
        $params = @{
                    SqlInstance = $testInstance;
                    Database = $testDatabase;
                    IndexColumnName = 'oBjEcT';
                    IndexColumnNameMatchType = 'Like';
                }
        $results = Find-DbaDbIndex @params
        It "Should find 1 indexes (LIKE search on ColumnName)" {
            $results.Count | Should Be 1
        }

    }
}