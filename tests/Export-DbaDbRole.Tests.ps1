#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaDbRole",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
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
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $AltExportPath = "$env:USERPROFILE\Documents"
        $outputFile1 = "$AltExportPath\Dbatoolsci_DbRole_CustomFile1.sql"
        
        $random = Get-Random
        $dbname1 = "dbatoolsci_exportdbadbrole$random"
        $login1 = "dbatoolsci_exportdbadbrole_login1$random"
        $user1 = "dbatoolsci_exportdbadbrole_user1$random"
        $dbRole = "dbatoolsci_SpExecute$random"

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $null = $server.Query("CREATE DATABASE [$dbname1]")
        $null = $server.Query("CREATE LOGIN [$login1] WITH PASSWORD = 'GoodPass1234!'")
        $server.Databases[$dbname1].ExecuteNonQuery("CREATE USER [$user1] FOR LOGIN [$login1]")

        $server.Databases[$dbname1].ExecuteNonQuery("ALTER ROLE [$dbRole] ADD MEMBER [$user1]")
        $server.Databases[$dbname1].ExecuteNonQuery("GRANT SELECT ON SCHEMA::dbo to [$dbRole]")
        $server.Databases[$dbname1].ExecuteNonQuery("GRANT EXECUTE ON SCHEMA::dbo to [$dbRole]")
        $server.Databases[$dbname1].ExecuteNonQuery("GRANT VIEW DEFINITION ON SCHEMA::dbo to [$dbRole]")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname1
        Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login1
        Remove-Item -Path $outputFile1 -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Check if output file was created" {
        BeforeAll {
            $null = Export-DbaDbRole -SqlInstance $TestConfig.instance2 -Database msdb -FilePath $outputFile1
        }

        It "Exports results to one sql file" {
            @(Get-ChildItem $outputFile1).Count | Should -BeExactly 1
        }
        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile1).Length | Should -BeGreaterThan 0
        }
    }

    Context "Check piping support" {
        BeforeAll {
            $role = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1 -Role $dbRole
            $null = $role | Export-DbaDbRole -FilePath $outputFile1
            $results = $role | Export-DbaDbRole -Passthru
        }

        It "Exports results to one sql file" {
            @(Get-ChildItem $outputFile1).Count | Should -BeExactly 1
        }
        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile1).Length | Should -BeGreaterThan 0
        }
        It "should include the defined BatchSeparator" {
            $results -match "GO" | Should -BeTrue
        }
        It "should include the role" {
            $results -match "CREATE ROLE \[$dbRole\]" | Should -BeTrue
        }
        It "should include GRANT EXECUTE ON SCHEMA" {
            $results -match "GRANT EXECUTE ON SCHEMA::\[dbo\] TO \[$dbRole\];" | Should -BeTrue
        }
        It "should include GRANT SELECT ON SCHEMA" {
            $results -match "GRANT SELECT ON SCHEMA::\[dbo\] TO \[$dbRole\];" | Should -BeTrue
        }
        It "should include GRANT VIEW DEFINITION ON SCHEMA" {
            $results -match "GRANT VIEW DEFINITION ON SCHEMA::\[dbo\] TO \[$dbRole\];" | Should -BeTrue
        }
        It "should include ALTER ROLE ADD MEMBER" {
            $results -match "ALTER ROLE \[$dbRole\] ADD MEMBER \[$user1\];" | Should -BeTrue
        }
    }
}