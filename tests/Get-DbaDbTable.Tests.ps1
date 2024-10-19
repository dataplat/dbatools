param($ModuleName = 'dbatools')

Describe "Get-DbaDbTable" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $dbname = "dbatoolsscidb_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $global:instance1 -Name $dbname -Owner sa
        $tablename = "dbatoolssci_$(Get-Random)"
        $null = Invoke-DbaQuery -SqlInstance $global:instance1 -Database $dbname -Query "Create table $tablename (col1 int)"
    }

    AfterAll {
        $null = Invoke-DbaQuery -SqlInstance $global:instance1 -Database $dbname -Query "drop table $tablename"
        $null = Remove-DbaDatabase -SqlInstance $global:instance1 -Database $dbname -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbTable
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "IncludeSystemDBs",
                "Table",
                "Schema",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Should get the table" {
        It "Gets the table" {
            $result = Get-DbaDbTable -SqlInstance $global:instance1
            $result.Name | Should -Contain $tablename
        }
        It "Gets the table when you specify the database" {
            $result = Get-DbaDbTable -SqlInstance $global:instance1 -Database $dbname
            $result.Name | Should -Contain $tablename
        }
    }

    Context "Should not get the table if database is excluded" {
        It "Doesn't find the table" {
            $result = Get-DbaDbTable -SqlInstance $global:instance1 -ExcludeDatabase $dbname
            $result.Name | Should -Not -Contain $tablename
        }
    }
}
