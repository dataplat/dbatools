#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Import-DbaPfDataCollectorSetTemplate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "DisplayName",
                "SchedulesEnabled",
                "RootPath",
                "Segment",
                "SegmentMaxDuration",
                "SegmentMaxSize",
                "Subdirectory",
                "SubdirectoryFormat",
                "SubdirectoryFormatPattern",
                "Task",
                "TaskRunAsSelf",
                "TaskArguments",
                "TaskUserTextArguments",
                "StopOnCompletion",
                "Path",
                "Template",
                "Instance",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $collectorSetName = "Long Running Queries"

        $computerName = Resolve-DbaComputerName -ComputerName $TestConfig.InstanceSingle -Property ComputerName
        # Clean up any existing collector sets before starting
        $null = Get-DbaPfDataCollectorSet -ComputerName $computerName -CollectorSet $collectorSetName | Remove-DbaPfDataCollectorSet

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    BeforeEach {
        $null = Get-DbaPfDataCollectorSet -ComputerName $computerName -CollectorSet $collectorSetName | Remove-DbaPfDataCollectorSet
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $null = Get-DbaPfDataCollectorSet -ComputerName $computerName -CollectorSet $collectorSetName | Remove-DbaPfDataCollectorSet

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Verifying command returns all the required results with pipe" {
        It "returns only one (and the proper) template" {
            $results = Get-DbaPfDataCollectorSetTemplate -Template $collectorSetName | Import-DbaPfDataCollectorSetTemplate -ComputerName $computerName
            $results.Name | Should -Be $collectorSetName
            $results.ComputerName | Should -Be $computerName
        }

        It "returns only one (and the proper) template without pipe" {
            $results = Import-DbaPfDataCollectorSetTemplate -ComputerName $computerName -Template $collectorSetName
            $results.Name | Should -Be $collectorSetName
            $results.ComputerName | Should -Be $computerName
        }
    }

    Context "When a subdirectory is given" {
        It "Imports the collector set with that subdirectory" {
            # -Subdirectory was declared and documented but never written into the template (#10607).
            $splatImport = @{
                ComputerName = $computerName
                Template     = $collectorSetName
                Subdirectory = "dbatoolsci_sub"
            }
            $results = Import-DbaPfDataCollectorSetTemplate @splatImport
            $results.Name | Should -Be $collectorSetName
            $results.Subdirectory | Should -Be "dbatoolsci_sub"
        }
    }

    Context "When a subdirectory is given for a template without a Subdirectory element" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Unlike Long Running Queries, the four PAL templates carry no Subdirectory element.
            $palCollectorSetName = "PAL - SQL Server 2014 and Up"
            $null = Get-DbaPfDataCollectorSet -ComputerName $computerName -CollectorSet $palCollectorSetName | Remove-DbaPfDataCollectorSet

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Get-DbaPfDataCollectorSet -ComputerName $computerName -CollectorSet $palCollectorSetName | Remove-DbaPfDataCollectorSet

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Creates the element and imports the collector set with that subdirectory" {
            # The element was assigned as if it existed, which threw for these templates and skipped the import.
            $splatImportPal = @{
                ComputerName = $computerName
                Template     = $palCollectorSetName
                Subdirectory = "dbatoolsci_palsub"
            }
            $results = Import-DbaPfDataCollectorSetTemplate @splatImportPal
            $WarnVar | Should -BeNullOrEmpty
            $results.Name | Should -Be $palCollectorSetName
            $results.Subdirectory | Should -Be "dbatoolsci_palsub"
        }
    }
}
