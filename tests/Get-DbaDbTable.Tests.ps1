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
        It "Should have IncludeSystemDBs as a parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemDBs -Type Switch
        }
        It "Should have Table as a parameter" {
            $CommandUnderTest | Should -HaveParameter Table -Type String[]
        }
        It "Should have Schema as a parameter" {
            $CommandUnderTest | Should -HaveParameter Schema -Type String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
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
