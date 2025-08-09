#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaServerRole",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Validate parameters" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "InputObject",
                "ScriptingOptionsObject",
                "ServerRole",
                "ExcludeServerRole",
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

        # Create a directory for test output files
        $AltExportPath = "$env:USERPROFILE\Documents"
        $outputFile = "$AltExportPath\Dbatoolsci_ServerRole.sql"
        
        # Create test objects
        $random = Get-Random
        $login1 = "dbatoolsci_exportdbaserverrole_login1$random"
        $svRole = "dbatoolsci_ScriptPermissions$random"

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $null = $server.Query("CREATE LOGIN [$login1] WITH PASSWORD = 'GoodPass1234!'")
        $null = $server.Query("CREATE SERVER ROLE [$svRole] AUTHORIZATION [$login1]")
        $null = $server.Query("ALTER SERVER ROLE [dbcreator] ADD MEMBER [$svRole]")
        $null = $server.Query("GRANT CREATE TRACE EVENT NOTIFICATION TO [$svRole]")
        $null = $server.Query("DENY SELECT ALL USER SECURABLES TO [$svRole]")
        $null = $server.Query("GRANT VIEW ANY DEFINITION TO [$svRole]")
        $null = $server.Query("GRANT VIEW ANY DATABASE TO [$svRole]")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup all created objects.
        $null = Remove-DbaServerRole -SqlInstance $TestConfig.instance2 -ServerRole $svRole
        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login1

        # Remove test files
        Remove-Item -Path $outputFile -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Check if output file was created" {
        BeforeAll {
            $null = Export-DbaServerRole -SqlInstance $TestConfig.instance2 -FilePath $outputFile
        }

        It "Exports results to one sql file" {
            @(Get-ChildItem $outputFile).Count | Should -BeExactly 1
        }

        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should -BeGreaterThan 0
        }
    }

    Context "Check using piped input created" {
        BeforeAll {
            $role = Get-DbaServerRole -SqlInstance $TestConfig.instance2 -ServerRole $svRole
            $null = $role | Export-DbaServerRole -FilePath $outputFile
            $global:results = $role | Export-DbaServerRole -Passthru
        }

        It "Exports results to one sql file" {
            @(Get-ChildItem $outputFile).Count | Should -BeExactly 1
        }

        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should -BeGreaterThan 0
        }

        It "should include the defined BatchSeparator" {
            $global:results -match "GO" | Should -BeTrue
        }

        It "should include the role" {
            $global:results -match "CREATE SERVER ROLE \[$svRole\]" | Should -BeTrue
        }

        It "should include ADD MEMBER" {
            $global:results -match "ALTER SERVER ROLE \[dbcreator\] ADD MEMBER \[$svRole\]" | Should -BeTrue
        }

        It "should include GRANT CREATE TRACE EVENT" {
            $global:results -match "GRANT CREATE TRACE EVENT NOTIFICATION TO \[$svRole\]" | Should -BeTrue
        }

        It "should include DENY SELECT ALL USER SECURABLES" {
            $global:results -match "DENY SELECT ALL USER SECURABLES TO \[$svRole\]" | Should -BeTrue
        }

        It "should include VIEW ANY DEFINITION" {
            $global:results -match "GRANT VIEW ANY DEFINITION TO \[$svRole\];" | Should -BeTrue
        }

        It "should include GRANT VIEW ANY DATABASE" {
            $global:results -match "GRANT VIEW ANY DATABASE TO \[$svRole\];" | Should -BeTrue
        }
    }
}
