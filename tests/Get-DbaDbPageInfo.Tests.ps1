param($ModuleName = 'dbatools')

Describe "Get-DbaDbPageInfo" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbPageInfo
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "Schema",
            "Table",
            "InputObject",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
