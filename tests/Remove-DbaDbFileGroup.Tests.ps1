#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbFileGroup",
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
                "FileGroup",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $newDb1 = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $db1name
        $newDb2 = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $db2name
        $newDb3 = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $db3name

        $server.Query("ALTER DATABASE $db1name ADD FILEGROUP $fileGroup1Name;")
        $server.Query("ALTER DATABASE $db2name ADD FILEGROUP $fileGroup1Name;")
        $server.Query("ALTER DATABASE $db3name ADD FILEGROUP $fileGroup1Name;")
        $server.Query("ALTER DATABASE $db1name ADD FILEGROUP $fileGroup2Name;")
        $server.Query("ALTER DATABASE $db1name ADD FILEGROUP $fileGroup3Name;")
        $server.Query("ALTER DATABASE $db1name ADD FILEGROUP $fileGroup4Name;")
        $server.Query("ALTER DATABASE $db1name ADD FILEGROUP $fileGroup5Name;")
        $server.Query("ALTER DATABASE $db1name ADD FILEGROUP $fileGroup6Name;")
        $server.Query("ALTER DATABASE $db1name ADD FILE (NAME = test1, FILENAME = '$($server.MasterDBPath)\test1.ndf') TO FILEGROUP $fileGroup2Name;")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $newDb1, $newDb2, $newDb3 | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When removing filegroups" {
        It "Removes filegroups" {
            $results = @(Get-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name, $db3name -FileGroup $fileGroup1Name, $fileGroup3Name)
            $results.Count | Should -Be 3
            Remove-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name, $db3name -FileGroup $fileGroup1Name, $fileGroup3Name -WarningAction SilentlyContinue -WarningVariable WarnVar
            $WarnVar | Should -Match "Filegroup FG3 does not exist in the database $db3name"
            $results = @(Get-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name, $db3name -FileGroup $fileGroup1Name, $fileGroup3Name)
            $results | Should -BeNullOrEmpty
        }

        It "Tries to remove a non-existent filegroup" {
            Remove-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup invalidFileGroupName -WarningVariable warnings -WarningAction SilentlyContinue
            $warnings | Should -BeLike "*Filegroup invalidFileGroupName does not exist in the database $db1name on $($TestConfig.instance2)"
        }

        It "Tries to remove a filegroup that still has files" {
            Remove-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup $fileGroup2Name -WarningVariable warnings -WarningAction SilentlyContinue
            $warnings | Should -BeLike "*Filegroup $fileGroup2Name is not empty. Before the filegroup can be dropped the files must be removed in $fileGroup2Name on $db1name on $($TestConfig.instance2)"
        }

        It "Removes a filegroup using a database from a pipeline and a filegroup from a pipeline" {
            $results = @(Get-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db2name -FileGroup $fileGroup1Name)
            $results.Count | Should -Be 1
            $newDb2 | Remove-DbaDbFileGroup -FileGroup $fileGroup1Name
            $results = @(Get-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db2name -FileGroup $fileGroup1Name)
            $results | Should -BeNullOrEmpty

            $results = @(Get-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup $fileGroup4Name, $fileGroup5Name)
            $results.Count | Should -Be 2
            $results[0], $newDb1 | Remove-DbaDbFileGroup -FileGroup $fileGroup5Name
            $results = @(Get-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup $fileGroup4Name, $fileGroup5Name)
            $results | Should -BeNullOrEmpty

            $fileGroup6 = Get-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup $fileGroup6Name
            $fileGroup6 | Should -Not -BeNullOrEmpty
            $fileGroup6 | Remove-DbaDbFileGroup
            $fileGroup6 = Get-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup $fileGroup6Name
            $fileGroup6 | Should -BeNullOrEmpty
        }
    }
}