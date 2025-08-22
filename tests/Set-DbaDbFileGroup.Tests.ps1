#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbFileGroup",
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
                "Default",
                "ReadOnly",
                "AutoGrowAllFiles",
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

        # Set variables. They are available in all the It blocks.
        $random = Get-Random
        $db1name = "dbatoolsci_filegroup_test_$random"
        $fileGroup1Name = "FG1"
        $fileGroup2Name = "FG2"
        $fileGroupROName = "FG1RO"

        # Create the objects.
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $newDb1 = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $db1name

        $server.Query("ALTER DATABASE $db1name ADD FILEGROUP $fileGroup1Name")
        $server.Query("ALTER DATABASE $db1name ADD FILEGROUP $fileGroup2Name")
        $server.Query("ALTER DATABASE $db1name ADD FILEGROUP $fileGroupROName")
        $server.Query("ALTER DATABASE $db1name ADD FILE (NAME = test1, FILENAME = '$($server.MasterDBPath)\test1.ndf') TO FILEGROUP $fileGroup1Name")
        $server.Query("ALTER DATABASE $db1name ADD FILE (NAME = testRO, FILENAME = '$($server.MasterDBPath)\testRO.ndf') TO FILEGROUP $fileGroupROName")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $db1name -Confirm:$false

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When setting filegroup properties" {

        It "Sets the options for default, readonly, readwrite, autogrow all files, and not autogrow all files" {
            $results = Set-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup $fileGroup1Name -Default -AutoGrowAllFiles -Confirm:$false
            $results.Name | Should -Be $fileGroup1Name
            $results.AutogrowAllFiles | Should -Be $true
            $results.IsDefault | Should -Be $true

            $results = Set-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup $fileGroup1Name -AutoGrowAllFiles:$false -Confirm:$false
            $results.Name | Should -Be $fileGroup1Name
            $results.AutogrowAllFiles | Should -Be $false

            $results = Set-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup $fileGroupROName -ReadOnly -Confirm:$false
            $results.Name | Should -Be $fileGroupROName
            $results.AutogrowAllFiles | Should -Be $false
            $results.IsDefault | Should -Be $false
            $results.ReadOnly | Should -Be $true

            $results = Set-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup $fileGroup1Name, $fileGroupROName -ReadOnly:$false -Confirm:$false
            $results.Name | Should -Be $fileGroup1Name, $fileGroupROName
            $results.ReadOnly | Should -Be $false, $false
        }

        It "A warning is returned when trying to set the options for a filegroup that doesn't exist" {
            $results = Set-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup invalidFileGroupName -Default -AutoGrowAllFiles -Confirm:$false -WarningVariable WarnVar -WarningAction SilentlyContinue
            $WarnVar | Should -BeLike "*Filegroup invalidFileGroupName does not exist in the database $db1name on $($TestConfig.instance2)"
        }

        It "A warning is returned when trying to set the options for an empty filegroup" {
            $results = Set-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup $fileGroup2Name -Default -AutoGrowAllFiles -Confirm:$false -WarningVariable WarnVar -WarningAction SilentlyContinue
            $WarnVar | Should -BeLike "*Filegroup $fileGroup2Name is empty on $db1name on $($TestConfig.instance2). Before the options can be set there must be at least one file in the filegroup."
        }

        It "Sets the filegroup options using a database from a pipeline and a filegroup from a pipeline" {
            $results = $newDb1 | Set-DbaDbFileGroup -FileGroup Primary -Default -Confirm:$false
            $results.Name | Should -Be Primary
            $results.IsDefault | Should -Be $true

            $results = Get-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup $fileGroup1Name | Set-DbaDbFileGroup -Default -Confirm:$false
            $results.Name | Should -Be $fileGroup1Name
            $results.IsDefault | Should -Be $true

            $fg1 = Get-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup $fileGroup1Name
            $results = $fg1, $newDb1 | Set-DbaDbFileGroup -FileGroup Primary -AutoGrowAllFiles -Confirm:$false
            $results.Name | Should -Be $fileGroup1Name, Primary
            $results.AutoGrowAllFiles | Should -Be $true, $true
        }
    }
}