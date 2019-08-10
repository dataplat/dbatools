$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'InputObject', 'ScriptingOptionsObject', 'Database', 'Role', 'ExcludeRole', 'ExcludeFixedRole', 'IncludeRoleMember', 'Path', 'FilePath', 'Passthru', 'BatchSeparator', 'NoClobber', 'Append', 'DestinationVersion', 'NoPrefix', 'Encoding', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $AltExportPath = "$env:USERPROFILE\Documents"
        $outputFile1 = "$AltExportPath\Dbatoolsci_DbRole_CustomFile1.sql"
        try {
            $random = Get-Random
            $dbname1 = "dbatoolsci_exportdbadbrole$random"
            $login1 = "dbatoolsci_exportdbadbrole_login1$random"
            $user1 = "dbatoolsci_exportdbadbrole_user1$random"
            $dbRole = "dbatoolsci_SpExecute$random"

            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $null = $server.Query("CREATE DATABASE [$dbname1]")
            $null = $server.Query("CREATE LOGIN [$login1] WITH PASSWORD = 'GoodPass1234!'")
            $server.Databases[$dbname1].ExecuteNonQuery("CREATE USER [$user1] FOR LOGIN [$login1]")

            $server.Databases[$dbname1].ExecuteNonQuery("ALTER ROLE [$dbRole] ADD MEMBER [$user1]")
            $server.Databases[$dbname1].ExecuteNonQuery("GRANT SELECT ON SCHEMA::dbo to [$dbRole]")
            $server.Databases[$dbname1].ExecuteNonQuery("GRANT EXECUTE ON SCHEMA::dbo to [$dbRole]")
            $server.Databases[$dbname1].ExecuteNonQuery("GRANT VIEW DEFINITION ON SCHEMA::dbo to [$dbRole]")
        } catch {}
    }
    AfterAll {
        try {
            Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbname1 -Confirm:$false
            Remove-DbaLogin -SqlInstance $script:instance2 -Login $login1 -Confirm:$false
        } catch { }
        (Get-ChildItem $outputFile1 -ErrorAction SilentlyContinue) | Remove-Item -ErrorAction SilentlyContinue
    }

    Context "Check if output file was created" {

        $null = Export-DbaDbRole -SqlInstance $script:instance2 -Database msdb -FilePath $outputFile1
        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile1).Count | Should Be 1
        }
        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile1).Length | Should BeGreaterThan 0
        }
    }

    Context "Check piping support" {

        $role = Get-DbaDbRole -SqlInstance $script:instance2 -Database $dbname1 -Role $dbRole
        $null = $role | Export-DbaDbRole -FilePath $outputFile1
        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile1).Count | Should Be 1
        }
        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile1).Length | Should BeGreaterThan 0
        }

        $script:results = $role | Export-DbaDbRole -Passthru
        It "should include the defined BatchSeparator" {
            $script:results -match "GO"
        }
        It "should include the role" {
            $script:results -match "CREATE ROLE [$dbRole]"
        }
        It "should include GRANT EXECUTE ON SCHEMA" {
            $script:results -match "GRANT EXECUTE ON SCHEMA::[dbo] TO [$dbRole];"
        }
        It "should include GRANT SELECT ON SCHEMA" {
            $script:results -match "GRANT SELECT ON SCHEMA::[dbo] TO [$dbRole];"
        }
        It "should include GRANT VIEW DEFINITION ON SCHEMA" {
            $script:results -match "GRANT VIEW DEFINITION ON SCHEMA::[dbo] TO [$dbRole];"
        }
        It "should include ALTER ROLE ADD MEMBER" {
            $script:results -match "ALTER ROLE [$dbRole] ADD MEMBER [$user1];"
        }
    }
}