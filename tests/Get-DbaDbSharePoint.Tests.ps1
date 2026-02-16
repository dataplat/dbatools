#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbSharePoint",
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
                "ConfigDatabase",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip {
    # Skip IntegrationTests because they need to be tested first.

    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

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

        Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        foreach ($db in $spdb) {
            try {
                $null = $server.Query("Create Database [$db]")
            } catch {
                continue
            }
        }

        # Andreas Jordan: We should try to get a backup working again or even better just a sql script to set this up.
        # This takes a long time but I cannot figure out why every backup of this db is malformed
        $bacpac = "$($TestConfig.appveyorlabrepo)\bacpac\sharepoint_config.bacpac"
        if (Test-Path -Path $bacpac) {
            $sqlpackage = (Get-Command sqlpackage -ErrorAction Ignore).Source
            if (-not $sqlpackage) {
                $libraryPath = Get-DbatoolsLibraryPath
                if ($libraryPath -match "desktop$") {
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
            # . $sqlpackage /Action:Import /tsn:$TestConfig.InstanceSingle /tdn:Sharepoint_Config /sf:$bacpac /p:Storage=File
            $skip = $true
        } else {
            Write-Warning -Message "No bacpac found in path [$bacpac], skipping tests."
            $skip = $true
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $spdb -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command gets SharePoint Databases" {
        BeforeAll {
            $results = Get-DbaDbSharePoint -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
        }

        It "returns $db from in the SharePoint database list" {
            foreach ($db in $spdb) {
                $db | Should -BeIn $results.Name
            }
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Database]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "Status",
                "IsAccessible",
                "RecoveryModel",
                "LogReuseWaitStatus",
                "SizeMB",
                "Compatibility",
                "Collation",
                "Owner",
                "Encrypted",
                "LastFullBackup",
                "LastDiffBackup",
                "LastLogBackup"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.Database"
        }
    }
}