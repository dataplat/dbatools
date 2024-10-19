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
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "ModifiedSince",
                "Type",
                "ExcludeSystemDatabases",
                "ExcludeSystemObjects",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
