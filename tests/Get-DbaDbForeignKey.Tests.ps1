param($ModuleName = 'dbatools')

Describe "Get-DbaDbForeignKey Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Importing the function if needed
        # . "$PSScriptRoot\$ModuleName.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbForeignKey
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have ExcludeSystemTable parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSystemTable
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

Describe "Get-DbaDbForeignKey Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $random = Get-Random
        $tableName = "dbatools_getdbtbl1"
        $tableName2 = "dbatools_getdbtbl2"
        $fkName = "dbatools_getdbfk"
        $dbname = "dbatoolsci_getdbfk$random"
        $server.Query("CREATE DATABASE $dbname")
        $server.Query("CREATE TABLE $tableName (idTbl1 INT PRIMARY KEY)", $dbname)
        $server.Query("CREATE TABLE $tableName2 (idTbl2 INT, idTbl1 INT)", $dbname)
        $server.Query("ALTER TABLE $tableName2 ADD CONSTRAINT $fkName FOREIGN KEY (idTbl1) REFERENCES $tableName (idTbl1) ON UPDATE NO ACTION ON DELETE NO ACTION ", $dbname)
    }

    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $global:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
    }

    Context "Command actually works" {
        It "returns no foreign keys from excluded DB with -ExcludeDatabase" {
            $results = Get-DbaDbForeignKey -SqlInstance $global:instance2 -ExcludeDatabase master
            $results.where( { $_.Database -eq 'master' }).count | Should -Be 0
        }
        It "returns only foreign keys from selected DB with -Database" {
            $results = Get-DbaDbForeignKey -SqlInstance $global:instance2 -Database $dbname
            $results.where( { $_.Database -ne 'master' }).count | Should -Be 1
        }
        It "Should include test foreign keys: $fkName" {
            $results = Get-DbaDbForeignKey -SqlInstance $global:instance2 -Database $dbname -ExcludeSystemTable
            ($results | Where-Object Name -eq $fkName).Name | Should -Be $fkName
        }
        It "Should exclude system tables" {
            $results = Get-DbaDbForeignKey -SqlInstance $global:instance2 -Database master -ExcludeSystemTable
            ($results | Where-Object Name -eq 'spt_fallback_db') | Should -BeNullOrEmpty
        }
    }

    Context "Parameters are returned correctly" {
        BeforeAll {
            $results = Get-DbaDbForeignKey -SqlInstance $global:instance2 -ExcludeDatabase master
        }
        It "Has the correct default properties" {
            $expectedStdProps = 'ComputerName,CreateDate,Database,DateLastModified,ID,InstanceName,IsChecked,IsEnabled,Name,NotForReplication,ReferencedKey,ReferencedTable,ReferencedTableSchema,SqlInstance,Table'.split(',')
            ($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($ExpectedStdProps | Sort-Object)
        }
        It "Has the correct properties" {
            $ExpectedProps = "Columns,ComputerName,CreateDate,Database,DatabaseEngineEdition,DatabaseEngineType,DateLastModified,DeleteAction,ExecutionManager,ExtendedProperties,ID,InstanceName,IsChecked,IsDesignMode,IsEnabled,IsFileTableDefined,IsMemoryOptimized,IsSystemNamed,Name,NotForReplication,Parent,ParentCollection,Properties,ReferencedKey,ReferencedTable,ReferencedTableSchema,ScriptReferencedTable,ScriptReferencedTableSchema,ServerVersion,SqlInstance,State,Table,UpdateAction,Urn,UserData".split(',')
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
    }
}
