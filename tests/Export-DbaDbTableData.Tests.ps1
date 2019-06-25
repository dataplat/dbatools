$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'InputObject', 'Path', 'FilePath', 'Encoding', 'BatchSeparator', 'NoPrefix', 'Passthru', 'NoClobber', 'Append', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database tempdb
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
        $results = Get-DbaDbTable -SqlInstance $script:instance1 -Database tempdb -Table dbatoolsci_example | Export-DbaDbTableData -Passthru
        "$results" | Should -match $escaped
        $results = Get-DbaDbTable -SqlInstance $script:instance1 -Database tempdb -Table dbatoolsci_temp | Export-DbaDbTableData -Passthru
        "$results" | Should -Match $secondescaped
    }

    It "supports piping more than one table" {
        $escaped = [regex]::escape('INSERT [dbo].[dbatoolsci_example] ([id]) VALUES (1)')
        $secondescaped = [regex]::escape('INSERT [dbo].[dbatoolsci_temp] ([name], [database_id],')
        $results = Get-DbaDbTable -SqlInstance $script:instance1 -Database tempdb -Table dbatoolsci_example, dbatoolsci_temp | Export-DbaDbTableData -Passthru
        "$results" | Should -match $escaped
        "$results" | Should -match $secondescaped
    }
}