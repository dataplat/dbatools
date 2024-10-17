param($ModuleName = 'dbatools')

Describe "Remove-DbaDbSynonym" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $dbname = "dbatoolsscidb_$(Get-Random)"
        $dbname2 = "dbatoolsscidb_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $global:instance2 -Name $dbname
        $null = New-DbaDatabase -SqlInstance $global:instance2 -Name $dbname2
    }

    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbname, $dbname2 -Confirm:$false
        $null = Remove-DbaDbSynonym -SqlInstance $global:instance2 -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbSynonym
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type String[]
        }
        It "Should have Schema as a parameter" {
            $CommandUnderTest | Should -HaveParameter Schema -Type String[]
        }
        It "Should have ExcludeSchema as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSchema -Type String[]
        }
        It "Should have Synonym as a parameter" {
            $CommandUnderTest | Should -HaveParameter Synonym -Type String[]
        }
        It "Should have ExcludeSynonym as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSynonym -Type String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Functionality" {
        It 'Removes Synonyms' {
            $null = New-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname -Synonym 'syn1' -BaseObject 'obj1'
            $null = New-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname -Synonym 'syn2' -BaseObject 'obj2'
            $result1 = Get-DbaDbSynonym -SqlInstance $global:instance2
            Remove-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname -Synonym 'syn1' -Confirm:$false
            $result2 = Get-DbaDbSynonym -SqlInstance $global:instance2

            $result1.Count | Should -BeGreaterThan $result2.Count
            $result2.Name | Should -Not -Contain 'syn1'
            $result2.Name | Should -Contain 'syn2'
        }

        It 'Accepts a list of synonyms' {
            $null = New-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname -Synonym 'syn3' -BaseObject 'obj3'
            $null = New-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname -Synonym 'syn4' -BaseObject 'obj4'
            $result3 = Get-DbaDbSynonym -SqlInstance $global:instance2 -Synonym 'syn3','syn4'
            Remove-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname -Synonym 'syn3','syn4' -Confirm:$false
            $result4 = Get-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname

            $result3.Count | Should -BeGreaterThan $result4.Count
            $result4.Name | Should -Not -Contain 'syn3'
            $result4.Name | Should -Not -Contain 'syn4'
        }

        It 'Excludes Synonyms' {
            $null = New-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname -Synonym 'syn5' -BaseObject 'obj5'
            $null = New-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname -Synonym 'syn6' -BaseObject 'obj6'
            $result5 = Get-DbaDbSynonym -SqlInstance $global:instance2
            Remove-DbaDbSynonym -SqlInstance $global:instance2 -ExcludeSynonym 'syn5' -Confirm:$false
            $result6 = Get-DbaDbSynonym -SqlInstance $global:instance2

            $result5.Count | Should -BeGreaterThan $result6.Count
            $result6.Name | Should -Not -Contain 'syn6'
            $result6.Name | Should -Contain 'syn5'
        }

        It 'Accepts input from Get-DbaDbSynonym' {
            $null = New-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname -Synonym 'syn7' -BaseObject 'obj7'
            $result7 = Get-DbaDbSynonym -SqlInstance $global:instance2 -Synonym 'syn5','syn7'
            $result7 | Remove-DbaDbSynonym -Confirm:$false
            $result8 = Get-DbaDbSynonym -SqlInstance $global:instance2

            $result7.Name | Should -Contain 'syn5'
            $result7.Name | Should -Contain 'syn7'
            $result8.Name | Should -Not -Contain 'syn5'
            $result8.Name | Should -Not -Contain 'syn7'
        }

        It 'Excludes Synonyms in a specified database' {
            $null = New-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname -Synonym 'syn10' -BaseObject 'obj10'
            $null = New-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname2 -Synonym 'syn11' -BaseObject 'obj11'
            $result11 = Get-DbaDbSynonym -SqlInstance $global:instance2
            Remove-DbaDbSynonym -SqlInstance $global:instance2 -ExcludeDatabase $dbname2 -Confirm:$false
            $result12 = Get-DbaDbSynonym -SqlInstance $global:instance2

            $result11.Count | Should -BeGreaterThan $result12.Count
            $result12.Database | Should -Not -Contain $dbname
            $result12.Database | Should -Contain $dbname2
        }

        It 'Excludes Synonyms in a specified schema' {
            $null = New-DbaDbSchema -SqlInstance $global:instance2 -Database $dbname2 -Schema 'sch2'
            $null = New-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname -Synonym 'syn12' -BaseObject 'obj12'
            $null = New-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname2 -Synonym 'syn13' -BaseObject 'obj13' -Schema 'sch2'
            $result13 = Get-DbaDbSynonym -SqlInstance $global:instance2
            Remove-DbaDbSynonym -SqlInstance $global:instance2 -ExcludeSchema 'sch2' -Confirm:$false
            $result14 = Get-DbaDbSynonym -SqlInstance $global:instance2

            $result13.Count | Should -BeGreaterThan $result14.Count
            $result13.Schema | Should -Contain 'dbo'
            $result14.Schema | Should -Not -Contain 'dbo'
            $result14.Schema | Should -Contain 'sch2'
        }

        It 'Accepts a list of schemas' {
            $null = New-DbaDbSchema -SqlInstance $global:instance2 -Database $dbname -Schema 'sch3'
            $null = New-DbaDbSchema -SqlInstance $global:instance2 -Database $dbname2 -Schema 'sch4'
            $null = New-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname -Synonym 'syn14' -BaseObject 'obj14' -Schema 'sch3'
            $null = New-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname2 -Synonym 'syn15' -BaseObject 'obj15' -Schema 'sch4'
            $null = New-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname2 -Synonym 'syn16' -BaseObject 'obj15' -Schema 'dbo'
            $result15 = Get-DbaDbSynonym -SqlInstance $global:instance2
            Remove-DbaDbSynonym -SqlInstance $global:instance2 -Schema 'sch3', 'dbo' -Confirm:$false
            $result16 = Get-DbaDbSynonym -SqlInstance $global:instance2

            $result15.Count | Should -BeGreaterThan $result16.Count
            $result16.Schema | Should -Not -Contain 'sch3'
            $result16.Schema | Should -Not -Contain 'dbo'
            $result16.Schema | Should -Contain 'sch4'
        }

        It 'Accepts a list of databases' {
            $null = New-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname -Synonym 'syn17' -BaseObject 'obj17'
            $null = New-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname2 -Synonym 'syn18' -BaseObject 'obj18'
            $result17 = Get-DbaDbSynonym -SqlInstance $global:instance2
            Remove-DbaDbSynonym -SqlInstance $global:instance2 -Database $dbname, $dbname2 -Confirm:$false
            $result18 = Get-DbaDbSynonym -SqlInstance $global:instance2

            $result17.Count | Should -BeGreaterThan $result18.Count
            $result18.Database | Should -Not -Contain $dbname
            $result18.Database | Should -Not -Contain $dbname2
        }

        It 'Throws an error when no input is provided' {
            { Remove-DbaDbSynonym -ErrorAction Stop } | Should -Throw -ExpectedMessage 'You must pipe in a synonym, database, or server or specify a SqlInstance'
        }
    }
}
