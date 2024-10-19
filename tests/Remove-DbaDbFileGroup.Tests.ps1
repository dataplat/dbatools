param($ModuleName = 'dbatools')

Describe "Remove-DbaDbFileGroup Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbFileGroup
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have FileGroup as a parameter" {
            $CommandUnderTest | Should -HaveParameter FileGroup
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

Describe "Remove-DbaDbFileGroup Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $db1name = "dbatoolsci_filegroup_test_$random"
        $db2name = "dbatoolsci_filegroup_test2_$random"
        $db3name = "dbatoolsci_filegroup_test3_$random"
        $fileGroup1Name = "FG1"
        $fileGroup2Name = "FG2"
        $fileGroup3Name = "FG3"
        $fileGroup4Name = "FG4"
        $fileGroup5Name = "FG5"
        $fileGroup6Name = "FG6"

        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $newDb1 = New-DbaDatabase -SqlInstance $global:instance2 -Name $db1name
        $newDb2 = New-DbaDatabase -SqlInstance $global:instance2 -Name $db2name
        $newDb3 = New-DbaDatabase -SqlInstance $global:instance2 -Name $db3name

        $server.Query("ALTER DATABASE $db1name ADD FILEGROUP $fileGroup1Name;")
        $server.Query("ALTER DATABASE $db2name ADD FILEGROUP $fileGroup1Name;")
        $server.Query("ALTER DATABASE $db3name ADD FILEGROUP $fileGroup1Name;")
        $server.Query("ALTER DATABASE $db1name ADD FILEGROUP $fileGroup2Name;")
        $server.Query("ALTER DATABASE $db1name ADD FILEGROUP $fileGroup3Name;")
        $server.Query("ALTER DATABASE $db1name ADD FILEGROUP $fileGroup4Name;")
        $server.Query("ALTER DATABASE $db1name ADD FILEGROUP $fileGroup5Name;")
        $server.Query("ALTER DATABASE $db1name ADD FILEGROUP $fileGroup6Name;")
        $server.Query("ALTER DATABASE $db1name ADD FILE (NAME = test1, FILENAME = '$($server.MasterDBPath)\test1.ndf') TO FILEGROUP $fileGroup2Name;")
    }

    AfterAll {
        $newDb1, $newDb2, $newDb3 | Remove-DbaDatabase -Confirm:$false
    }

    Context "Command works" {
        It "Removes filegroups" {
            $results = Get-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db1name, $db3name -FileGroup $fileGroup1Name, $fileGroup3Name
            $results.Length | Should -Be 3
            Remove-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db1name, $db3name -FileGroup $fileGroup1Name, $fileGroup3Name -Confirm:$false
            $results = Get-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db1name, $db3name -FileGroup $fileGroup1Name, $fileGroup3Name
            $results | Should -BeNullOrEmpty
        }

        It "Tries to remove a non-existent filegroup" {
            Remove-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db1name -FileGroup invalidFileGroupName -Confirm:$false -WarningVariable warnings
            $warnings | Should -BeLike "*Filegroup invalidFileGroupName does not exist in the database $db1name on $global:instance2"
        }

        It "Tries to remove a filegroup that still has files" {
            Remove-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db1name -FileGroup $fileGroup2Name -Confirm:$false -WarningVariable warnings
            $warnings | Should -BeLike "*Filegroup $fileGroup2Name is not empty. Before the filegroup can be dropped the files must be removed in $fileGroup2Name on $db1name on $global:instance2"
        }

        It "Removes a filegroup using a database from a pipeline and a filegroup from a pipeline" {
            $results = Get-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db2name -FileGroup $fileGroup1Name
            $results.Length | Should -Be 1
            $newDb2 | Remove-DbaDbFileGroup -FileGroup $fileGroup1Name -Confirm:$false
            $results = Get-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db2name -FileGroup $fileGroup1Name
            $results | Should -BeNullOrEmpty

            $results = Get-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db1name -FileGroup $fileGroup4Name, $fileGroup5Name
            $results.Length | Should -Be 2
            $results[0], $newDb1 | Remove-DbaDbFileGroup -FileGroup $fileGroup5Name -Confirm:$false
            $results = Get-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db1name -FileGroup $fileGroup4Name, $fileGroup5Name
            $results | Should -BeNullOrEmpty

            $fileGroup6 = Get-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db1name -FileGroup $fileGroup6Name
            $fileGroup6 | Should -Not -BeNullOrEmpty
            $fileGroup6 | Remove-DbaDbFileGroup -Confirm:$false
            $fileGroup6 = Get-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db1name -FileGroup $fileGroup6Name
            $fileGroup6 | Should -BeNullOrEmpty
        }
    }
}
