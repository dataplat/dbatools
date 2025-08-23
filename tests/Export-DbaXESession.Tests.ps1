#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaXESession",
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
                "Session",
                "Path",
                "FilePath",
                "Encoding",
                "Passthru",
                "BatchSeparator",
                "NoPrefix",
                "NoClobber",
                "Append",
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

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Explain what needs to be set up for the test:
        # To test Export-DbaXESession, we need a valid SQL instance with at least one Extended Events session.
        # We will use the system_health session which is always available.

        # Set variables. They are available in all the It blocks.
        $outputFile = "$backupPath\Dbatoolsci_XE_CustomFile.sql"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Check if output file was created" {
        BeforeAll {
            $null = Export-DbaXESession -SqlInstance $TestConfig.instance2 -FilePath $outputFile
        }

        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile).Count | Should -BeExactly 1
        }

        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should -BeGreaterThan 0
        }
    }

    Context "Check if session parameter is honored" {
        BeforeAll {
            # Remove previous output file if exists
            Remove-Item -Path $outputFile -ErrorAction SilentlyContinue
            $null = Export-DbaXESession -SqlInstance $TestConfig.instance2 -FilePath $outputFile -Session system_health
        }

        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile).Count | Should -BeExactly 1
        }

        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should -BeGreaterThan 0
        }
    }

    Context "Check if supports Pipeline input" {
        BeforeAll {
            # Remove previous output file if exists
            Remove-Item -Path $outputFile -ErrorAction SilentlyContinue
            $null = Get-DbaXESession -SqlInstance $TestConfig.instance2 -Session system_health | Export-DbaXESession -FilePath $outputFile
        }

        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile).Count | Should -BeExactly 1
        }

        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should -BeGreaterThan 0
        }
    }
}