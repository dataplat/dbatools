param($ModuleName = 'dbatools')

Describe "Export-DbaDbTableData" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaDbTableData
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Table[] -Mandatory:$false
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type String -Mandatory:$false
        }
        It "Should have FilePath as a parameter" {
            $CommandUnderTest | Should -HaveParameter FilePath -Type String -Mandatory:$false
        }
        It "Should have Encoding as a parameter" {
            $CommandUnderTest | Should -HaveParameter Encoding -Type String -Mandatory:$false
        }
        It "Should have BatchSeparator as a parameter" {
            $CommandUnderTest | Should -HaveParameter BatchSeparator -Type String -Mandatory:$false
        }
        It "Should have NoPrefix as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoPrefix -Type Switch -Mandatory:$false
        }
        It "Should have Passthru as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Passthru -Type Switch -Mandatory:$false
        }
        It "Should have NoClobber as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoClobber -Type Switch -Mandatory:$false
        }
        It "Should have Append as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Append -Type Switch -Mandatory:$false
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
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
