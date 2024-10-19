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
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter of type Microsoft.SqlServer.Management.Smo.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a non-mandatory parameter of type System.Object[]" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase as a non-mandatory parameter of type System.Object[]" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have ModifiedSince as a non-mandatory parameter of type System.DateTime" {
            $CommandUnderTest | Should -HaveParameter ModifiedSince
        }
        It "Should have Type as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter Type
        }
        It "Should have ExcludeSystemDatabases as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSystemDatabases
        }
        It "Should have ExcludeSystemObjects as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSystemObjects
        }
        It "Should have InputObject as a non-mandatory parameter of type Microsoft.SqlServer.Management.Smo.Database[]" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Modules are properly retrieved" {
        BeforeAll {
            $results = Get-DbaModule -SqlInstance $global:instance1 | Select-Object -First 101
        }

        It "Should have a high count" {
            $results.Count | Should -BeGreaterThan 100
        }

        It "Should only have one type of object when filtering by View" {
            $viewResults = Get-DbaModule -SqlInstance $global:instance1 -Type View -Database msdb
            ($viewResults | Select-Object -Unique Type | Measure-Object).Count | Should -Be 1
        }

        It "Should only have one database when filtering by msdb" {
            $msdbResults = Get-DbaModule -SqlInstance $global:instance1 -Type View -Database msdb
            ($msdbResults | Select-Object -Unique Database | Measure-Object).Count | Should -Be 1
        }
    }

    Context "Accepts Piped Input" {
        BeforeAll {
            $db = Get-DbaDatabase -SqlInstance $global:instance1 -Database msdb, master
            $results = $db | Get-DbaModule
        }

        It "Should have a high count" {
            $results.Count | Should -BeGreaterThan 100
        }

        It "Should only have two databases" {
            ($results | Select-Object -Unique Database | Measure-Object).Count | Should -Be 2
        }

        It "Should only have one type of object when filtering by View" {
            $viewResults = Get-DbaDatabase -SqlInstance $global:instance1 -Database msdb | Get-DbaModule -Type View
            ($viewResults | Select-Object -Unique Type | Measure-Object).Count | Should -Be 1
        }

        It "Should only have one database when filtering by msdb" {
            $msdbResults = Get-DbaDatabase -SqlInstance $global:instance1 -Database msdb | Get-DbaModule -Type View
            ($msdbResults | Select-Object -Unique Database | Measure-Object).Count | Should -Be 1
        }
    }
}
