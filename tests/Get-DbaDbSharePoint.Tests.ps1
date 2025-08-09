#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbSharePoint",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "ConfigDatabase",
                "InputObject",
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

        $skip = $false
        $spdb = @(
            "SharePoint_Admin_7c0c491d0e6f43858f75afa5399d49ab",
            "WSS_Logging",
            "SecureStoreService_20e1764876504335a6d8dd0b1937f4bf",
            "DefaultWebApplicationDB",
            "SharePoint_Config_4c524cb90be44c6f906290fe3e34f2e0",
            "DefaultPowerPivotServiceApplicationDB-5b638361-c6fc-4ad9-b8ba-d05e63e48ac6",
            "SharePoint_Config_4c524cb90be44c6f906290fe3e34f2e0"
        )

        Get-DbaProcess -SqlInstance $TestConfig.instance2 -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2

        foreach ($db in $spdb) {
            try {
                $null = $server.Query("Create Database [$db]")
            } catch { continue }
        }

        # Andreas Jordan: We should try to get a backup working again or even better just a sql script to set this up.
        # This takes a long time but I cannot figure out why every backup of this db is malformed
        $bacpac = "$($TestConfig.appveyorlabrepo)\bacpac\sharepoint_config.bacpac"
        
        if (Test-Path -Path $bacpac) {
            $sqlpackage = (Get-Command sqlpackage -ErrorAction Ignore).Source
            if (-not $sqlpackage) {
                $libraryPath = Get-DbatoolsLibraryPath
                if ($libraryPath -match 'desktop$') {
                    $sqlpackage = Join-DbaPath -Path (Get-DbatoolsLibraryPath) -ChildPath lib, dac, sqlpackage.exe
                } elseif ($isWindows) {
                    $sqlpackage = Join-DbaPath -Path (Get-DbatoolsLibraryPath) -ChildPath lib, dac, sqlpackage.exe
                } else {
                    # Not implemented
                }
            }
            # On PowerShell 5.1 on Windows Server 2022, the following line throws:
            # sqlpackage.exe : *** An unexpected failure occurred: Could not load type 'Microsoft.Data.Tools.Schema.Common.Telemetry.SqlPackageSource' from assembly 'Microsoft.Data.Tools.Utilities, Version=162.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a'.
            # On PowerShell 7.4.2 on Windows Server 2022, the following line throws:
            # Unhandled Exception: System.IO.FileNotFoundException: Could not load file or assembly 'System.ValueTuple, Version=4.0.3.0, Culture=neutral, PublicKeyToken=cc7b13ffcd2ddd51' or one of its dependencies. The system cannot find the file specified.
            # So we don't run the following line but skip the tests
            # . $sqlpackage /Action:Import /tsn:$TestConfig.instance2 /tdn:Sharepoint_Config /sf:$bacpac /p:Storage=File
            $skip = $true
        } else {
            Write-Warning -Message "No bacpac found in path [$bacpac], skipping tests."
            $skip = $true
        }

        # Store skip value globally for use in It blocks
        $global:skipIntegrationTests = $skip

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $spdb -Confirm:$false -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Command gets SharePoint Databases" {
        BeforeAll {
            $results = Get-DbaDbSharePoint -SqlInstance $TestConfig.instance2
        }

        It "Returns SharePoint_Admin_7c0c491d0e6f43858f75afa5399d49ab from in the SharePoint database list" -Skip:$global:skipIntegrationTests {
            "SharePoint_Admin_7c0c491d0e6f43858f75afa5399d49ab" | Should -BeIn $results.Name
        }

        It "Returns WSS_Logging from in the SharePoint database list" -Skip:$global:skipIntegrationTests {
            "WSS_Logging" | Should -BeIn $results.Name
        }

        It "Returns SecureStoreService_20e1764876504335a6d8dd0b1937f4bf from in the SharePoint database list" -Skip:$global:skipIntegrationTests {
            "SecureStoreService_20e1764876504335a6d8dd0b1937f4bf" | Should -BeIn $results.Name
        }

        It "Returns DefaultWebApplicationDB from in the SharePoint database list" -Skip:$global:skipIntegrationTests {
            "DefaultWebApplicationDB" | Should -BeIn $results.Name
        }

        It "Returns SharePoint_Config_4c524cb90be44c6f906290fe3e34f2e0 from in the SharePoint database list" -Skip:$global:skipIntegrationTests {
            "SharePoint_Config_4c524cb90be44c6f906290fe3e34f2e0" | Should -BeIn $results.Name
        }

        It "Returns DefaultPowerPivotServiceApplicationDB-5b638361-c6fc-4ad9-b8ba-d05e63e48ac6 from in the SharePoint database list" -Skip:$global:skipIntegrationTests {
            "DefaultPowerPivotServiceApplicationDB-5b638361-c6fc-4ad9-b8ba-d05e63e48ac6" | Should -BeIn $results.Name
        }
    }
}