#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Mount-DbaDatabase",
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
                "Database",
                "FileStructure",
                "DatabaseOwner",
                "AttachOption",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $tempDir = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Type Container -Path $tempDir

        # Setup removes, restores and backups on the local drive for Mount-DbaDatabase
        $null = Restore-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Path "$($TestConfig.appveyorlabrepo)\detachattach\detachattach.bak"
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database detachattach | Backup-DbaDatabase -BackupFileName $tempDir\detachattach.bak
        $null = Dismount-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database detachattach -Force

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database detachattach | Remove-DbaDatabase
        Remove-Item -Path $tempDir -Force -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Attaches a single database and tests to ensure the alias still exists" {
        BeforeAll {
            $results = Mount-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database detachattach
        }

        It "Should return success" {
            $results.AttachResult | Should -Be "Success"
        }

        It "Should return that the database is only Database" {
            $results.Database | Should -Be "detachattach"
        }

        It "Should return that the AttachOption default is None" {
            $results.AttachOption | Should -Be "None"
        }
    }
}