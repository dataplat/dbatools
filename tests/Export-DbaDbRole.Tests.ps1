param($ModuleName = 'dbatools')

Describe "Export-DbaDbRole Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaDbRole
        }
        It "has all the required parameters" {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "InputObject",
                "ScriptingOptionsObject",
                "Database",
                "Role",
                "ExcludeRole",
                "ExcludeFixedRole",
                "IncludeRoleMember",
                "Path",
                "FilePath",
                "Passthru",
                "BatchSeparator",
                "NoClobber",
                "Append",
                "NoPrefix",
                "Encoding",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }
}

Describe "Export-DbaDbRole Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $AltExportPath = "$env:USERPROFILE\Documents"
        $outputFile1 = "$AltExportPath\Dbatoolsci_DbRole_CustomFile1.sql"
        $random = Get-Random
        $dbname1 = "dbatoolsci_exportdbadbrole$random"
        $login1 = "dbatoolsci_exportdbadbrole_login1$random"
        $user1 = "dbatoolsci_exportdbadbrole_user1$random"
        $dbRole = "dbatoolsci_SpExecute$random"

        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $null = $server.Query("CREATE DATABASE [$dbname1]")
        $null = $server.Query("CREATE LOGIN [$login1] WITH PASSWORD = 'GoodPass1234!'")
        $server.Databases[$dbname1].ExecuteNonQuery("CREATE USER [$user1] FOR LOGIN [$login1]")

        $server.Databases[$dbname1].ExecuteNonQuery("CREATE ROLE [$dbRole]")
        $server.Databases[$dbname1].ExecuteNonQuery("ALTER ROLE [$dbRole] ADD MEMBER [$user1]")
        $server.Databases[$dbname1].ExecuteNonQuery("GRANT SELECT ON SCHEMA::dbo to [$dbRole]")
        $server.Databases[$dbname1].ExecuteNonQuery("GRANT EXECUTE ON SCHEMA::dbo to [$dbRole]")
        $server.Databases[$dbname1].ExecuteNonQuery("GRANT VIEW DEFINITION ON SCHEMA::dbo to [$dbRole]")
    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbname1 -Confirm:$false
        Remove-DbaLogin -SqlInstance $global:instance2 -Login $login1 -Confirm:$false
        Remove-Item -Path $outputFile1 -ErrorAction SilentlyContinue
    }

    Context "Check if output file was created" {
        BeforeAll {
            $null = Export-DbaDbRole -SqlInstance $global:instance2 -Database msdb -FilePath $outputFile1
        }

        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile1).Count | Should -Be 1
        }

        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile1).Length | Should -BeGreaterThan 0
        }
    }

    Context "Check piping support" {
        BeforeAll {
            $role = Get-DbaDbRole -SqlInstance $global:instance2 -Database $dbname1 -Role $dbRole
            $null = $role | Export-DbaDbRole -FilePath $outputFile1
            $global:results = $role | Export-DbaDbRole -Passthru
        }

        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile1).Count | Should -Be 1
        }

        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile1).Length | Should -BeGreaterThan 0
        }

        It "should include the defined BatchSeparator" {
            $global:results | Should -Match "GO"
        }

        It "should include the role" {
            $global:results | Should -Match "CREATE ROLE [$dbRole]"
        }

        It "should include GRANT EXECUTE ON SCHEMA" {
            $global:results | Should -Match "GRANT EXECUTE ON SCHEMA::\[dbo\] TO \[$dbRole\];"
        }

        It "should include GRANT SELECT ON SCHEMA" {
            $global:results | Should -Match "GRANT SELECT ON SCHEMA::\[dbo\] TO \[$dbRole\];"
        }

        It "should include GRANT VIEW DEFINITION ON SCHEMA" {
            $global:results | Should -Match "GRANT VIEW DEFINITION ON SCHEMA::\[dbo\] TO \[$dbRole\];"
        }

        It "should include ALTER ROLE ADD MEMBER" {
            $global:results | Should -Match "ALTER ROLE \[$dbRole\] ADD MEMBER \[$user1\];"
        }
    }
}
