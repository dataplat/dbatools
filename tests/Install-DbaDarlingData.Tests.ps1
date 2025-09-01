#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Install-DbaDarlingData",
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
                "Branch",
                "Database",
                "LocalFile",
                "Procedure",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:$env:appveyor {
    # Skip IntegrationTests on AppVeyor because they fail for unknown reasons.

    Context "Testing DarlingData installer with download" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $darlingDbDownload = "dbatoolsci_darling_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance3
            $server.Query("CREATE DATABASE $darlingDbDownload")

            $resultsDownload = Install-DbaDarlingData -SqlInstance $TestConfig.instance3 -Database $darlingDbDownload -Branch main -Force -Verbose:$false

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Remove-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $darlingDbDownload

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Installs to specified database: $darlingDbDownload" {
            $resultsDownload[0].Database | Should -Be $darlingDbDownload
        }

        It "Shows status of Installed" {
            $resultsDownload[0].Status | Should -Be "Installed"
        }

        It "has the correct properties" {
            $result = $resultsDownload[0]
            $ExpectedProps = "SqlInstance", "InstanceName", "ComputerName", "Name", "Status", "Database"
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
    }

    Context "Testing DarlingData installer with LocalFile" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $darlingDbLocalFile = "dbatoolsci_darling_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance3
            $server.Query("CREATE DATABASE $darlingDbLocalFile")

            $outfile = "DarlingData-main.zip"
            Invoke-WebRequest -Uri "https://github.com/erikdarlingdata/DarlingData/archive/main.zip" -OutFile $outfile
            if (Test-Path $outfile) {
                $fullOutfile = (Get-ChildItem $outfile).FullName
            }
            $resultsLocalFile = Install-DbaDarlingData -SqlInstance $TestConfig.instance3 -Database $darlingDbLocalFile -Branch main -LocalFile $fullOutfile -Force

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Remove-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $darlingDbLocalFile

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Installs to specified database: $darlingDbLocalFile" {
            $resultsLocalFile[0].Database | Should -Be $darlingDbLocalFile
        }

        It "Shows status of Installed" {
            $resultsLocalFile[0].Status | Should -Be "Installed"
        }

        It "Has the correct properties" {
            $result = $resultsLocalFile[0]
            $ExpectedProps = "SqlInstance", "InstanceName", "ComputerName", "Name", "Status", "Database"
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
    }
}