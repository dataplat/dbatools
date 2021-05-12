$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Schema', 'ExcludeSchema', 'Synonym', 'ExcludeSynonym', 'InputObject', 'EnableException'
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
        $null = New-DbaDbSchema -SqlInstance $script:instance2 -Database $dbname2 -Schema sch2
        $null = New-DbaDbSynonym -SqlInstance $script:instance2 -Database $dbname, $dbname2 -Synonym syn1 -BaseObject obj1
        $null = New-DbaDbSynonym -SqlInstance $script:instance2 -Database $dbname -Synonym syn2 -BaseObject obj2
        $null = New-DbaDbSynonym -SqlInstance $script:instance2 -Database $dbname2 -Schema sch2 -Synonym syn2 -BaseObject obj2
    }
    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbname, $dbname2 -Confirm:$false
        $null = Remove-DbaDbSynonym -SqlInstance $script:instance2
    }

    Context "Functionality" {
        It 'Returns Results' {
            $result = Get-DbaDbSynonym -SqlInstance $script:instance2

            $result.Count | Should -Be 4
        }

        It 'Returns all synonyms for all databases' {
            $result = Get-DbaDbSynonym -SqlInstance $script:instance2

            $uniqueDatabases = $result.Database | Select-Object -Unique
            $uniqueDatabases.Count | Should -Be 2
            $result.Count | Should -Be 4
        }

        It 'Accepts a list of databases' {
            $result = Get-DbaDbSynonym -SqlInstance $script:instance2 -Database $dbname, $dbname2

            $result.Database | Select-Object -Unique| Should -Be $dbname, $dbname2
        }

        It 'Excludes databases' {
            $result = Get-DbaDbSynonym -SqlInstance $script:instance2 -ExcludeDatabase $dbname2

            $uniqueDatabases = $result.Database | Select-Object -Unique
            $uniqueDatabases.Count | Should -BeExactly 1
            $uniqueDatabases | Should -Not -Contain $dbname2
        }

        It 'Accepts a list of synonyms' {
            $result = Get-DbaDbSynonym -SqlInstance $script:instance2 -Synonym 'syn1', 'syn2'

            $result.Name | Select-Object -Unique | Should -Be 'syn1', 'syn2'
        }

        It 'Excludes synonyms' {
            $result = Get-DbaDbSynonym -SqlInstance $script:instance2 -ExcludeSynonym 'syn2'

            $result.Name | Select-Object -Unique | Should -Not -Contain 'syn2'
        }

        It 'Finds synonyms for specified schema only' {
            $result = Get-DbaDbSynonym -SqlInstance $script:instance2 -Schema 'sch2'

            $result.Count | Should -Be 1
        }

        It 'Accepts a list of schemas' {
            $result = Get-DbaDbSynonym -SqlInstance $script:instance2 -Schema 'dbo','sch2'

            $result.Schema | Select-Object -Unique | Should -Be 'dbo','sch2'
        }

        It 'Excludes schemas' {
            $result = Get-DbaDbSynonym -SqlInstance $script:instance2 -ExcludeSchema 'dbo'

            $result.Schema | Select-Object -Unique | Should -Not -Contain 'dbo'
        }

    }
}