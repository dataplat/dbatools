param($ModuleName = 'dbatools')

Describe "Get-DbaDbPageInfo" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbPageInfo
        }
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Database as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.String[] -Mandatory:$false
        }
        It "Should have Schema as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter Schema -Type System.String[] -Mandatory:$false
        }
        It "Should have Table as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter Table -Type System.String[] -Mandatory:$false
        }
        It "Should have InputObject as a non-mandatory parameter of type Microsoft.SqlServer.Management.Smo.Database[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Database[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.Switch -Mandatory:$false
        }
    }

    Context "Command usage" {
        BeforeAll {
            $random = Get-Random
            $dbname = "dbatoolsci_pageinfo_$random"
            Get-DbaProcess -SqlInstance $global:instance2 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $server.Query("CREATE DATABASE $dbname;")
            $server.Databases[$dbname].Query('CREATE TABLE [dbo].[TestTable](TestText VARCHAR(MAX) NOT NULL)')
            $query = "
                    INSERT INTO dbo.TestTable
                    (
                        TestText
                    )
                    VALUES
                    ('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')"

            # Generate a bunch of extra inserts to create enough pages
            1..100 | ForEach-Object {
                $query += ",('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')"
            }
            $server.Databases[$dbname].Query($query)
        }

        AfterAll {
            Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbname -Confirm:$false
        }

        It "returns the proper results" {
            $result = Get-DbaDbPageInfo -SqlInstance $global:instance2 -Database $dbname
            $result.Count | Should -Be 9
            ($result | Where-Object { $_.IsAllocated -eq $false }).Count | Should -Be 5
            ($result | Where-Object { $_.IsAllocated -eq $true }).Count | Should -Be 4
        }
    }
}
