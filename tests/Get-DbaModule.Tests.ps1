param($ModuleName = 'dbatools')

Describe "Get-DbaModule" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaModule
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database as a non-mandatory parameter of type Object[]" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[] -Not -Mandatory
        }
        It "Should have ExcludeDatabase as a non-mandatory parameter of type Object[]" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[] -Not -Mandatory
        }
        It "Should have ModifiedSince as a non-mandatory parameter of type DateTime" {
            $CommandUnderTest | Should -HaveParameter ModifiedSince -Type DateTime -Not -Mandatory
        }
        It "Should have Type as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Type -Type String[] -Not -Mandatory
        }
        It "Should have ExcludeSystemDatabases as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSystemDatabases -Type Switch -Not -Mandatory
        }
        It "Should have ExcludeSystemObjects as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSystemObjects -Type Switch -Not -Mandatory
        }
        It "Should have InputObject as a non-mandatory parameter of type Database[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[] -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Modules are properly retrieved" {
        BeforeAll {
            $results = Get-DbaModule -SqlInstance $env:instance1 | Select-Object -First 101
        }

        It "Should have a high count" {
            $results.Count | Should -BeGreaterThan 100
        }

        It "Should only have one type of object when filtering by View" {
            $viewResults = Get-DbaModule -SqlInstance $env:instance1 -Type View -Database msdb
            ($viewResults | Select-Object -Unique Type | Measure-Object).Count | Should -Be 1
        }

        It "Should only have one database when filtering by msdb" {
            $msdbResults = Get-DbaModule -SqlInstance $env:instance1 -Type View -Database msdb
            ($msdbResults | Select-Object -Unique Database | Measure-Object).Count | Should -Be 1
        }
    }

    Context "Accepts Piped Input" {
        BeforeAll {
            $db = Get-DbaDatabase -SqlInstance $env:instance1 -Database msdb, master
            $results = $db | Get-DbaModule
        }

        It "Should have a high count" {
            $results.Count | Should -BeGreaterThan 100
        }

        It "Should only have two databases" {
            ($results | Select-Object -Unique Database | Measure-Object).Count | Should -Be 2
        }

        It "Should only have one type of object when filtering by View" {
            $viewResults = Get-DbaDatabase -SqlInstance $env:instance1 -Database msdb | Get-DbaModule -Type View
            ($viewResults | Select-Object -Unique Type | Measure-Object).Count | Should -Be 1
        }

        It "Should only have one database when filtering by msdb" {
            $msdbResults = Get-DbaDatabase -SqlInstance $env:instance1 -Database msdb | Get-DbaModule -Type View
            ($msdbResults | Select-Object -Unique Database | Measure-Object).Count | Should -Be 1
        }
    }
}
