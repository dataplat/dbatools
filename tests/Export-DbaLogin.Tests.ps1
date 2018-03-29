$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

$outputFile = "dbatoolsci_exportdbalogin.sql"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        try {
            $random = Get-Random
            $dbname1 = "dbatoolsci_exportdbalogin1$random"
            $login1 = "dbatoolsci_exportdbalogin_login1$random"
            $user1 = "dbatoolsci_exportdbalogin_user1$random"
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $null = $server.Query("CREATE DATABASE [$dbname1]")
            $null = $server.Query("CREATE LOGIN [$login1] WITH PASSWORD = 'GoodPass1234!'")
            $server.Databases[$dbname1].ExecuteNonQuery("CREATE USER [$user1] FOR LOGIN [$login1]")

            $dbname2 = "dbatoolsci_exportdbalogin2$random"
            $login2 = "dbatoolsci_exportdbalogin_login2$random"
            $user2 = "dbatoolsci_exportdbalogin_user2$random"
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $null = $server.Query("CREATE DATABASE [$dbname2]")
            $null = $server.Query("CREATE LOGIN [$login2] WITH PASSWORD = 'GoodPass1234!'")
            $null = $server.Query("ALTER LOGIN [$login2] DISABLE")
            $null = $server.Query("DENY CONNECT SQL TO [$login2]")

            if ($server.VersionMajor -lt 11) {
                $null = $server.Query("EXEC sys.sp_addsrvrolemember @rolename=N'dbcreator', @loginame=N'$login2'")
            } else {
                $null = $server.Query("ALTER SERVER ROLE [dbcreator] ADD MEMBER [$login2]")
            }
            $null = $server.Query("GRANT SELECT ON sys.databases TO [$login2] WITH GRANT OPTION")
            $server.Databases[$dbname2].ExecuteNonQuery("CREATE USER [$user2] FOR LOGIN [$login2]")
        }
        catch { } # No idea why appveyor can't handle this
    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname1 -Confirm:$false
        Remove-DbaLogin -SqlInstance $script:instance1 -Login $login1 -Confirm:$false

        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname2 -Confirm:$false
        Remove-DbaLogin -SqlInstance $script:instance1 -Login $login2 -Confirm:$false

        Remove-Item -Path $outputFile
    }

    It "Filters to specific databases" {
        $output = Export-DbaLogin -SqlInstance $script:instance1 -Database $dbname1 -EnableException

        ([regex]::matches($output, 'USE \[.*?\]').Value | Select-Object -Unique).Count | Should Be 1
    }

    It "Doesn't include database details when using NoDatabase" {
        $output = Export-DbaLogin -SqlInstance $script:instance1 -NoDatabase -EnableException

        ([regex]::matches($output, 'USE \[.*?\]')).Count | Should Be 0
    }

    $output = Export-DbaLogin -SqlInstance $script:instance1 -EnableException
    It "Doesn't filter specific databases" {
        ([regex]::matches($output, 'USE \[.*?\]').Value | Select-Object -Unique).Count | Should BeGreaterThan 1
    }

    It "Exports disabled logins" {
        [regex]::matches($output, "ALTER LOGIN \[.*?\] DISABLE").Count | Should BeGreaterThan 0
    }

    It "Exports deny connects" {
        [regex]::matches($output, "DENY CONNECT SQL TO \[.*?\]").Count | Should BeGreaterThan 0
    }

    It "Exports system role memberships" {
        if ($server.VersionMajor -lt 11) {
            [regex]::matches($output, "EXEC sys.sp_addsrvrolemember @rolename=N'dbcreator', @loginame=N'$login2'").Count | Should BeGreaterThan 0
        } else {
            [regex]::matches($output, "ALTER SERVER ROLE \[.*?\] ADD MEMBER \[.*?\]").Count | Should BeGreaterThan 0
        }
    }

    It "Exports to the specified file" {
        Export-DbaLogin -SqlInstance $script:instance1 -FilePath $outputFile -EnableException

        Test-Path -Path $outputFile | Should Be $true
    }
}