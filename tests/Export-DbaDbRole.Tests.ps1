#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaDbRole",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
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
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $altExportPath = "$env:USERPROFILE\Documents"
        $outputFile1 = "$altExportPath\Dbatoolsci_DbRole_CustomFile1.sql"
        $resourcesToCleanup = @($outputFile1)

        $random = Get-Random
        $dbname1 = "dbatoolsci_exportdbadbrole$random"
        $login1 = "dbatoolsci_exportdbadbrole_login1$random"
        $user1 = "dbatoolsci_exportdbadbrole_user1$random"
        $dbRole = "dbatoolsci_SpExecute$random"

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $null = $server.Query("CREATE DATABASE [$dbname1]")
        $null = $server.Query("CREATE LOGIN [$login1] WITH PASSWORD = 'GoodPass1234!'")
        $server.Databases[$dbname1].ExecuteNonQuery("CREATE USER [$user1] FOR LOGIN [$login1]")

        # The role itself was never created, so the ALTER ROLE below always threw and the catch
        # that used to wrap this whole block swallowed it. None of the objects the tests look for
        # existed, and the tests passed regardless because their assertions were never piped to
        # Should. The catch is gone as well, so a broken setup now fails the test loudly.
        $server.Databases[$dbname1].ExecuteNonQuery("CREATE ROLE [$dbRole]")
        $server.Databases[$dbname1].ExecuteNonQuery("ALTER ROLE [$dbRole] ADD MEMBER [$user1]")
        $server.Databases[$dbname1].ExecuteNonQuery("GRANT SELECT ON SCHEMA::dbo to [$dbRole]")
        $server.Databases[$dbname1].ExecuteNonQuery("GRANT EXECUTE ON SCHEMA::dbo to [$dbRole]")
        $server.Databases[$dbname1].ExecuteNonQuery("GRANT VIEW DEFINITION ON SCHEMA::dbo to [$dbRole]")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        try {
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname1
            Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $login1
        } catch {
            # Ignore cleanup errors
        }

        Remove-Item -Path $resourcesToCleanup -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Check if output file was created" {
        BeforeAll {
            $null = Export-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database msdb -FilePath $outputFile1
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
            $role = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database $dbname1 -Role $dbRole
            $null = $role | Export-DbaDbRole -FilePath $outputFile1
            $results = $role | Export-DbaDbRole -Passthru

            # Role membership is only scripted when it is asked for, so the membership test below
            # needs its own export. It used to assert against the default output, where the ALTER
            # ROLE line can never appear.
            $resultsWithMember = $role | Export-DbaDbRole -Passthru -IncludeRoleMember
        }

        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile1).Count | Should -Be 1
        }

        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile1).Length | Should -BeGreaterThan 0
        }

        It "should include the defined BatchSeparator" {
            ($results -join [Environment]::NewLine) | Should -Match "GO"
        }

        It "should include the role" {
            ($results -join [Environment]::NewLine) | Should -Match ([regex]::Escape("CREATE ROLE [$dbRole]"))
        }

        It "should include GRANT EXECUTE ON SCHEMA" {
            ($results -join [Environment]::NewLine) | Should -Match ([regex]::Escape("GRANT EXECUTE ON SCHEMA::[dbo] TO [$dbRole];"))
        }

        It "should include GRANT SELECT ON SCHEMA" {
            ($results -join [Environment]::NewLine) | Should -Match ([regex]::Escape("GRANT SELECT ON SCHEMA::[dbo] TO [$dbRole];"))
        }

        It "should include GRANT VIEW DEFINITION ON SCHEMA" {
            ($results -join [Environment]::NewLine) | Should -Match ([regex]::Escape("GRANT VIEW DEFINITION ON SCHEMA::[dbo] TO [$dbRole];"))
        }

        It "should not include ALTER ROLE ADD MEMBER without IncludeRoleMember" {
            ($results -join [Environment]::NewLine) | Should -Not -Match ([regex]::Escape("ALTER ROLE [$dbRole] ADD MEMBER [$user1];"))
        }

        It "should include ALTER ROLE ADD MEMBER with IncludeRoleMember" {
            ($resultsWithMember -join [Environment]::NewLine) | Should -Match ([regex]::Escape("ALTER ROLE [$dbRole] ADD MEMBER [$user1];"))
        }
    }
}
