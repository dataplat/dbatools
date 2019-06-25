$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'Database', 'SqlCredential', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Testing if suspect pages are present" {
        BeforeAll {
            $dbname = "dbatoolsci_GetSuspectPage"
            $Server = Connect-DbaInstance -SqlInstance $script:instance2
            $null = $Server.Query("Create Database [$dbname]")
            $db = Get-DbaDatabase -SqlInstance $Server -Database $dbname
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $Server -Database $dbname -Confirm:$false
        }

        $null = $db.Query("
        CREATE TABLE dbo.[Example] (id int);
        INSERT dbo.[Example]
        SELECT top 1000 1
        FROM sys.objects")

        # make darn sure suspect pages show up, run twice
        try {
            $null = Invoke-DbaDbCorruption -SqlInstance $script:instance2 -Database $dbname -Confirm:$false
            $null = $db.Query("select top 100 from example")
            $null = $server.Query("ALTER DATABASE $dbname SET PAGE_VERIFY CHECKSUM  WITH NO_WAIT")
            $null = Start-DbccCheck -Server $Server -dbname $dbname -WarningAction SilentlyContinue
        } catch {} # should fail

        try {
            $null = Invoke-DbaDbCorruption -SqlInstance $script:instance2 -Database $dbname -Confirm:$false
            $null = $db.Query("select top 100 from example")
            $null = $server.Query("ALTER DATABASE $dbname SET PAGE_VERIFY CHECKSUM  WITH NO_WAIT")
            $null = Start-DbccCheck -Server $Server -dbname $dbname -WarningAction SilentlyContinue
        } catch { } # should fail

        $results = Get-DbaSuspectPage -SqlInstance $server
        It "function should find at least one record in suspect_pages table" {
            $results.Database -contains $dbname | Should Be $true
        }
    }
}