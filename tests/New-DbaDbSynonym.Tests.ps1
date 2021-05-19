$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Synonym', 'Schema', 'BaseServer', 'BaseDatabase', 'BaseSchema', 'BaseObject', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $dbname = "dbatoolsscidb_$(Get-Random)"
        $dbname2 = "dbatoolsscidb_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $script:instance2 -Name $dbname
        $null = New-DbaDatabase -SqlInstance $script:instance2 -Name $dbname2
    }
    AfterEach {
        $null = Remove-DbaDbSynonym -SqlInstance $script:instance2 -Confirm:$false
    }
    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbname, $dbname2 -Confirm:$false
        $null = Remove-DbaDbSynonym -SqlInstance $script:instance2 -Confirm:$false
    }

    Context "Functionality" {
        It 'Add new synonym and returns results' {
            $result1 = New-DbaDbSynonym -SqlInstance $script:instance2 -Database $dbname -Synonym 'syn1' -BaseObject 'obj1'

            $result1.Count | Should -Be 1
            $result1.Name | Should -Be syn1
            $result1.Database | Should -Be $dbname
            $result1.BaseObject | Should -Be 'obj1'
        }

        It 'Add new synonym with default schema' {
            $result2a = New-DbaDbSynonym -SqlInstance $script:instance2 -Database $dbname -Synonym 'syn2a' -BaseObject 'obj2a'

            $result2a.Count | Should -Be 1
            $result2a.Name | Should -Be 'syn2a'
            $result2a.Schema | Should -Be 'dbo'
            $result2a.Database | Should -Be $dbname
            $result2a.BaseObject | Should -Be 'obj2a'
        }

        It 'Add new synonym with specified schema' {
            $null = New-DbaDbSchema -SqlInstance $script:instance2 -Database $dbname -Schema 'sch2'
            $result2 = New-DbaDbSynonym -SqlInstance $script:instance2 -Database $dbname -Synonym 'syn2' -BaseObject 'obj2' -Schema 'sch2'

            $result2.Count | Should -Be 1
            $result2.Name | Should -Be 'syn2'
            $result2.Schema | Should -Be 'sch2'
            $result2.Database | Should -Be $dbname
            $result2.BaseObject | Should -Be 'obj2'
        }

        It 'Add new synonym to list of databases' {
            $result3 = New-DbaDbSynonym -SqlInstance $script:instance2 -Database $dbname, $dbname2 -Synonym 'syn3' -BaseObject 'obj3'

            $result3.Count | Should -Be 2
            $result3.Name | Select-Object -Unique | Should -Be 'syn3'
            $result3.Database | Should -Contain $dbname
            $result3.Database | Should -Contain $dbname2
            $result3.BaseObject | Should -Be 'obj3','obj3'
        }

        It 'Add new synonym to different schema' {
            $null = New-DbaDbSchema -SqlInstance $script:instance2 -Database $dbname -Schema 'sch4'
            $result4 = New-DbaDbSynonym -SqlInstance $script:instance2 -Database $dbname -Schema 'sch4' -Synonym 'syn4' -BaseObject 'obj4'

            $result4.Count | Should -Be 1
            $result4.Name | Select-Object -Unique | Should -Be 'syn4'
            $result4.Schema | Should -Contain 'sch4'
            $result4.Database | Should -Contain $dbname
            $result4.BaseSchema | Should -BeNullOrEmpty
            $result4.BaseDatabase | Should -BeNullOrEmpty
            $result4.BaseServer | Should -BeNullOrEmpty
            $result4.BaseObject | Should -Be 'obj4'
        }

        It 'Add new synonym to with a base schema' {
            $null = New-DbaDbSchema -SqlInstance $script:instance2 -Database $dbname -Schema 'sch5'
            $result5 = New-DbaDbSynonym -SqlInstance $script:instance2 -Database $dbname -Schema 'sch5' -Synonym 'syn5' -BaseObject 'obj5' -BaseSchema 'bsch5'

            $result5.Count | Should -Be 1
            $result5.Name | Select-Object -Unique | Should -Be 'syn5'
            $result5.Schema | Should -Contain 'sch5'
            $result5.Database | Should -Contain $dbname
            $result5.BaseSchema | Should -Contain 'bsch5'
            $result5.BaseDatabase | Should -BeNullOrEmpty
            $result5.BaseServer | Should -BeNullOrEmpty
            $result5.BaseObject | Should -Be 'obj5'
        }

        It 'Add new synonym to with a base database' {
            $null = New-DbaDbSchema -SqlInstance $script:instance2 -Database $dbname -Schema 'sch6'
            $result6 = New-DbaDbSynonym -SqlInstance $script:instance2 -Database $dbname -Schema 'sch6' -Synonym 'syn6' -BaseObject 'obj6' -BaseSchema 'bsch6' -BaseDatabase 'bdb6'

            $result6.Count | Should -Be 1
            $result6.Name | Select-Object -Unique | Should -Be 'syn6'
            $result6.Schema | Should -Contain 'sch6'
            $result6.Database | Should -Contain $dbname
            $result6.BaseSchema | Should -Contain 'bsch6'
            $result6.BaseDatabase | Should -Contain 'bdb6'
            $result6.BaseServer | Should -BeNullOrEmpty
            $result6.BaseObject | Should -Be 'obj6'
        }

        It 'Add new synonym to with a base server' {
            $null = New-DbaDbSchema -SqlInstance $script:instance2 -Database $dbname -Schema 'sch7'
            $result7 = New-DbaDbSynonym -SqlInstance $script:instance2 -Database $dbname -Schema 'sch7' -Synonym 'syn7' -BaseObject 'obj7' -BaseSchema 'bsch7' -BaseDatabase 'bdb7' -BaseServer 'bsrv7'

            $result7.Count | Should -Be 1
            $result7.Name | Select-Object -Unique | Should -Be 'syn7'
            $result7.Schema | Should -Contain 'sch7'
            $result7.Database | Should -Contain $dbname
            $result7.BaseSchema | Should -Contain 'bsch7'
            $result7.BaseDatabase | Should -Contain 'bdb7'
            $result7.BaseServer | Should -Contain 'bsrv7'
            $result7.BaseObject | Should -Be 'obj7'
        }

    }
}