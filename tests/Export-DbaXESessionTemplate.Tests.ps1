#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaXESessionTemplate",
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
                "Session",
                "Path",
                "FilePath",
                "InputObject",
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
        $tempPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $tempPath -ItemType Directory

        # Explain what needs to be set up for the test:
        # We need to ensure that any existing 'Profiler TSQL Duration' session is removed before we start

        # Set variables. They are available in all the It blocks.
        $sessionName = "Profiler TSQL Duration"

        # Clean up any existing session
        $null = Get-DbaXESession -SqlInstance $TestConfig.instance2 -Session $sessionName | Remove-DbaXESession

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Get-DbaXESession -SqlInstance $TestConfig.instance2 -Session $sessionName | Remove-DbaXESession

        # Remove the temporary directory and any exported files.
        Remove-Item -Path $tempPath -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Test Importing Session Template" {
        It "session exports to disk" {
            $session = Import-DbaXESessionTemplate -SqlInstance $TestConfig.instance2 -Template "Profiler TSQL Duration"
            $results = $session | Export-DbaXESessionTemplate -Path $tempPath
            $results.Name | Should -Be "$sessionName.xml"
        }
    }
}