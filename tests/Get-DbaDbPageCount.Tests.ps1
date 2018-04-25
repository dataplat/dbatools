$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tags "UnitTests" {

    BeforeAll {
        # Get a random value for the database name
        $random = Get-Random

        # Setup the database name
        $dbname = "dbatoolsci_pagecount_$random"

        # Remove the database if it exists
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Confirm:$false

        # Get a server object
        $server = Connect-DbaInstance -SqlInstance $script:instance1

        # Create the database
        $server.Query("CREATE DATABASE $dbname;")

        # Create the test table
        $server.Databases[$dbname].Query('CREATE TABLE [dbo].[TestTable](TestText VARCHAR(MAX) NOT NULL)')
    }

    AfterAll {
        # Remove the database if it exists
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Confirm:$false
    }

    Context "Count Pages" {
        # Setup the initial query
        $query = "
INSERT INTO dbo.TestTable
(
    TestText
)
VALUES
('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')"

        # Generate a bunch of extra inserts to create enough pages
        for ($i = 0; $i -lt 500; $i++) {
            $query += ",('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')"
        }

        # Execute the query
        $server.Databases[$dbname].Query($query)

        $result = Get-DbaDbPageCount -SqlInstance $script:instance1 -Database $dbname

        $result.TotalPages | Should Be 17
        $result.UnusedPages | Should Be 3
        $result.UsedPages | Should Be 14

    }

}