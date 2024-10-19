param($ModuleName = 'dbatools')

Describe "Get-DbaDbSynonym Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbSynonym
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
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have Schema as a parameter" {
            $CommandUnderTest | Should -HaveParameter Schema
        }
        It "Should have ExcludeSchema as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSchema
        }
        It "Should have Synonym as a parameter" {
            $CommandUnderTest | Should -HaveParameter Synonym
        }
        It "Should have ExcludeSynonym as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSynonym
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

Describe "Get-DbaDbSynonym Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    BeforeAll {
        $dbname = "dbatoolsscidb_$(Get-Random)"
        $dbname2 = "dbatoolsscidb2_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $global:instance2 -Name $dbname
        $null = New-DbaDatabase -SqlInstance $global:instance2 -Name $dbname2
        $null = New-DbaDbSchema -SqlInstance $global:instance2 -Database $dbname2 -Schema sch2
        $null = New-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname -Synonym syn1 -BaseObject obj1
        $null = New-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname2 -Synonym syn2 -BaseObject obj2
        $null = New-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname2 -Schema sch2 -Synonym syn3 -BaseObject obj2
    }

    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbname, $dbname2 -Confirm:$false
        $null = Remove-DbaDbSynonym -SqlInstance $global:instance2 -Confirm:$false
    }

    Context "Functionality" {
        It 'Returns Results' {
            $result1 = Get-DbaDbSynonym -SqlInstance $global:instance2
            $result1.Count | Should -BeGreaterThan 0
        }

        It 'Returns all synonyms for all databases' {
            $result2 = Get-DbaDbSynonym -SqlInstance $global:instance2
            $uniqueDatabases = $result2.Database | Select-Object -Unique
            $uniqueDatabases.Count | Should -BeGreaterThan 1
            $result2.Count | Should -BeGreaterThan 2
        }

        It 'Accepts a list of databases' {
            $result3 = Get-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname, $dbname2
            $result3.Database | Select-Object -Unique | Should -Be @($dbname, $dbname2)
        }

        It 'Excludes databases' {
            $result4 = Get-DbaDbSynonym -SqlInstance $global:instance2 -ExcludeDatabase $dbname2
            $uniqueDatabases = $result4.Database | Select-Object -Unique
            $uniqueDatabases | Should -Not -Contain $dbname2
        }

        It 'Accepts a list of synonyms' {
            $result5 = Get-DbaDbSynonym -SqlInstance $global:instance2 -Synonym 'syn1', 'syn2'
            $result5.Name | Select-Object -Unique | Should -Be @('syn1', 'syn2')
        }

        It 'Excludes synonyms' {
            $result6 = Get-DbaDbSynonym -SqlInstance $global:instance2 -ExcludeSynonym 'syn2'
            $result6.Name | Select-Object -Unique | Should -Not -Contain 'syn2'
        }

        It 'Finds synonyms for specified schema only' {
            $result7 = Get-DbaDbSynonym -SqlInstance $global:instance2 -Schema 'sch2'
            $result7.Count | Should -Be 1
        }

        It 'Accepts a list of schemas' {
            $result8 = Get-DbaDbSynonym -SqlInstance $global:instance2 -Schema 'dbo','sch2'
            $result8.Schema | Select-Object -Unique | Should -Be @('dbo','sch2')
        }

        It 'Excludes schemas' {
            $result9 = Get-DbaDbSynonym -SqlInstance $global:instance2 -ExcludeSchema 'dbo'
            $result9.Schema | Select-Object -Unique | Should -Not -Contain 'dbo'
        }

        It 'Throws when no input is provided' {
            { Get-DbaDbSynonym } | Should -Throw -ExpectedMessage 'You must pipe in a database or specify a SqlInstance'
        }
    }
}
