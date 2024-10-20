param($ModuleName = 'dbatools')

Describe "Export-DbaDbTableData" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaDbTableData
        }

        $params = @(
            "SqlInstance",
            "SqlCredential"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $db = Get-DbaDatabase -SqlInstance $global:instance1 -Database tempdb
            $null = $db.Query("CREATE TABLE dbo.dbatoolsci_example (id int);
                INSERT dbo.dbatoolsci_example
                SELECT top 10 1
                FROM sys.objects")
            $null = $db.Query("Select * into dbatoolsci_temp from sys.databases")
        }
        AfterAll {
            try {
                $null = $db.Query("DROP TABLE dbo.dbatoolsci_example")
                $null = $db.Query("DROP TABLE dbo.dbatoolsci_temp")
            } catch {
                $null = 1
            }
        }

        It "exports the table data" {
            $escaped = [regex]::escape('INSERT [dbo].[dbatoolsci_example] ([id]) VALUES (1)')
            $secondescaped = [regex]::escape('INSERT [dbo].[dbatoolsci_temp] ([name], [database_id],')
            $results = Get-DbaDbTable -SqlInstance $global:instance1 -Database tempdb -Table dbatoolsci_example | Export-DbaDbTableData -Passthru
            "$results" | Should -Match $escaped
            $results = Get-DbaDbTable -SqlInstance $global:instance1 -Database tempdb -Table dbatoolsci_temp | Export-DbaDbTableData -Passthru
            "$results" | Should -Match $secondescaped
        }

        It "supports piping more than one table" {
            $escaped = [regex]::escape('INSERT [dbo].[dbatoolsci_example] ([id]) VALUES (1)')
            $secondescaped = [regex]::escape('INSERT [dbo].[dbatoolsci_temp] ([name], [database_id],')
            $results = Get-DbaDbTable -SqlInstance $global:instance1 -Database tempdb -Table dbatoolsci_example, dbatoolsci_temp | Export-DbaDbTableData -Passthru
            "$results" | Should -Match $escaped
            "$results" | Should -Match $secondescaped
        }
    }
}
