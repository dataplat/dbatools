param($ModuleName = 'dbatools')

Describe "Get-DbaSuspectPage" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaSuspectPage
        }
        $params = @(
            "SqlInstance",
            "Database",
            "SqlCredential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Testing if suspect pages are present" {
        BeforeAll {
            $dbname = "dbatoolsci_GetSuspectPage"
            $Server = Connect-DbaInstance -SqlInstance $global:instance2
            $null = $Server.Query("Create Database [$dbname]")
            $db = Get-DbaDatabase -SqlInstance $Server -Database $dbname

            $null = $db.Query("
            CREATE TABLE dbo.[Example] (id int);
            INSERT dbo.[Example]
            SELECT top 1000 1
            FROM sys.objects")

            # make darn sure suspect pages show up, run twice
            try {
                $null = Invoke-DbaDbCorruption -SqlInstance $global:instance2 -Database $dbname
                $null = $db.Query("select top 100 from example")
                $null = $server.Query("ALTER DATABASE $dbname SET PAGE_VERIFY CHECKSUM  WITH NO_WAIT")
                $null = Start-DbccCheck -Server $Server -dbname $dbname -WarningAction SilentlyContinue
            } catch {} # should fail

            try {
                $null = Invoke-DbaDbCorruption -SqlInstance $global:instance2 -Database $dbname
                $null = $db.Query("select top 100 from example")
                $null = $server.Query("ALTER DATABASE $dbname SET PAGE_VERIFY CHECKSUM  WITH NO_WAIT")
                $null = Start-DbccCheck -Server $Server -dbname $dbname -WarningAction SilentlyContinue
            } catch { } # should fail
        }

        AfterAll {
            Remove-DbaDatabase -SqlInstance $Server -Database $dbname -Confirm:$false
        }

        It "function should find at least one record in suspect_pages table" {
            $results = Get-DbaSuspectPage -SqlInstance $server
            $results.Database | Should -Contain $dbname
        }
    }
}
