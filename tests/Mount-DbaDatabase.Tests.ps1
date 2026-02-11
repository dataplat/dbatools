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

    Context "Output validation" {
        BeforeAll {
            $outputTestDb = "dbatoolsci_mountoutput_$(Get-Random)"
            try {
                $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
                $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $outputTestDb
                $null = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $outputTestDb -Type Full -FilePath "$($TestConfig.Temp)\$outputTestDb.bak"
                $null = Dismount-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $outputTestDb -Force
                $outputResult = Mount-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $outputTestDb
                $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
            } catch {
                $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
                $outputResult = $null
            }
        }

        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $outputTestDb | Remove-DbaDatabase -Confirm:$false -ErrorAction SilentlyContinue
            Remove-Item -Path "$($TestConfig.Temp)\$outputTestDb.bak" -ErrorAction SilentlyContinue
        }

        It "Returns output of the expected type" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $outputResult | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "Database", "AttachResult", "AttachOption", "FileStructure")
            foreach ($prop in $expectedProps) {
                $outputResult.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}