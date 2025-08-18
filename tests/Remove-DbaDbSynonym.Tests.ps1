#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbSynonym",
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
                "ExcludeDatabase",
                "Schema",
                "ExcludeSchema",
                "Synonym",
                "ExcludeSynonym",
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

        $dbname = "dbatoolsscidb_$(Get-Random)"
        $dbname2 = "dbatoolsscidb_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $dbname
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $dbname2

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname, $dbname2 -Confirm:$false
        $null = Remove-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Confirm:$false

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Functionality" {
        It "Removes Synonyms" {
            $null = New-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname -Synonym "syn1" -BaseObject "obj1"
            $null = New-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname -Synonym "syn2" -BaseObject "obj2"
            $result1 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2
            Remove-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname -Synonym "syn1" -Confirm:$false
            $result2 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2

            $result1.Count | Should -BeGreaterThan $result2.Count
            $result2.Name | Should -Not -Contain "syn1"
            $result2.Name | Should -Contain "syn2"
        }

        It "Accepts a list of synonyms" {
            $null = New-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname -Synonym "syn3" -BaseObject "obj3"
            $null = New-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname -Synonym "syn4" -BaseObject "obj4"
            $result3 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Synonym "syn3", "syn4"
            Remove-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname -Synonym "syn3", "syn4" -Confirm:$false
            $result4 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname

            $result3.Count | Should -BeGreaterThan $result4.Count
            $result4.Name | Should -Not -Contain "syn3"
            $result4.Name | Should -Not -Contain "syn4"
        }

        It "Excludes Synonyms" {
            $null = New-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname -Synonym "syn5" -BaseObject "obj5"
            $null = New-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname -Synonym "syn6" -BaseObject "obj6"
            $result5 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2
            Remove-DbaDbSynonym -SqlInstance $TestConfig.instance2 -ExcludeSynonym "syn5" -Confirm:$false
            $result6 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2

            $result5.Count | Should -BeGreaterThan $result6.Count
            $result6.Name | Should -Not -Contain "syn6"
            $result6.Name | Should -Contain "syn5"
        }

        It "Accepts input from Get-DbaDbSynonym" {
            $null = New-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname -Synonym "syn7" -BaseObject "obj7"
            $result7 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Synonym "syn5", "syn7"
            $result7 | Remove-DbaDbSynonym -Confirm:$false
            $result8 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2

            $result7.Name | Should -Contain "syn5"
            $result7.Name | Should -Contain "syn7"
            $result8.Name | Should -Not -Contain "syn5"
            $result8.Name | Should -Not -Contain "syn7"
        }

        It "Excludes Synonyms in a specified database" {
            $null = New-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname -Synonym "syn10" -BaseObject "obj10"
            $null = New-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname2 -Synonym "syn11" -BaseObject "obj11"
            $result11 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2
            Remove-DbaDbSynonym -SqlInstance $TestConfig.instance2 -ExcludeDatabase $dbname2 -Confirm:$false
            $result12 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2

            $result11.Count | Should -BeGreaterThan $result12.Count
            $result12.Database | Should -Not -Contain $dbname
            $result12.Database | Should -Contain $dbname2
        }

        It "Excludes Synonyms in a specified schema" {
            $null = New-DbaDbSchema -SqlInstance $TestConfig.instance2 -Database $dbname2 -Schema "sch2"
            $null = New-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname -Synonym "syn12" -BaseObject "obj12"
            $null = New-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname2 -Synonym "syn13" -BaseObject "obj13" -Schema "sch2"
            $result13 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2
            Remove-DbaDbSynonym -SqlInstance $TestConfig.instance2 -ExcludeSchema "sch2" -Confirm:$false
            $result14 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2

            $result13.Count | Should -BeGreaterThan $result14.Count
            $result13.Schema | Should -Contain "dbo"
            $result14.Schema | Should -Not -Contain "dbo"
            $result14.Schema | Should -Contain "sch2"
        }

        It "Accepts a list of schemas" {
            $null = New-DbaDbSchema -SqlInstance $TestConfig.instance2 -Database $dbname -Schema "sch3"
            $null = New-DbaDbSchema -SqlInstance $TestConfig.instance2 -Database $dbname2 -Schema "sch4"
            $null = New-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname -Synonym "syn14" -BaseObject "obj14" -Schema "sch3"
            $null = New-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname2 -Synonym "syn15" -BaseObject "obj15" -Schema "sch4"
            $null = New-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname2 -Synonym "syn16" -BaseObject "obj15" -Schema "dbo"
            $result15 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2
            Remove-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Schema "sch3", "dbo" -Confirm:$false
            $result16 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2

            $result15.Count | Should -BeGreaterThan $result16.Count
            $result16.Schema | Should -Not -Contain "sch3"
            $result16.Schema | Should -Not -Contain "dbo"
            $result16.Schema | Should -Contain "sch4"
        }

        It "Accepts a list of databases" {
            $null = New-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname -Synonym "syn17" -BaseObject "obj17"
            $null = New-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname2 -Synonym "syn18" -BaseObject "obj18"
            $result17 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2
            Remove-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname, $dbname2 -Confirm:$false
            $result18 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2

            $result17.Count | Should -BeGreaterThan $result18.Count
            $result18.Database | Should -Not -Contain $dbname
            $result18.Database | Should -Not -Contain $dbname2
        }

        It "Input is provided" {
            $result20 = Remove-DbaDbSynonym -WarningAction SilentlyContinue -WarningVariable warn > $null

            $warn | Should -Match "You must pipe in a synonym, database, or server or specify a SqlInstance"
        }
    }
}