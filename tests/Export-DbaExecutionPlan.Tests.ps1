#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaExecutionPlan",
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
                "ExcludeDatabase",
                "Path",
                "SinceCreation",
                "SinceLastExecution",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Create a simple database and execute a query to populate plan cache
            $dbName = "dbatoolsci_exportplan_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
            $null = $server.Query("CREATE DATABASE [$dbName]")
            $null = $server.Query("SELECT * FROM sys.objects", $dbName)
            
            # Export the execution plan
            $exportPath = "$env:TEMP\dbatools_export_$(Get-Random)"
            $null = New-Item -ItemType Directory -Path $exportPath -Force
            $result = Export-DbaExecutionPlan -SqlInstance $TestConfig.instance1 -Database $dbName -Path $exportPath -EnableException
        }

        AfterAll {
            # Cleanup
            if ($dbName) {
                Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbName -Confirm:$false
            }
            if ($exportPath -and (Test-Path $exportPath)) {
                Remove-Item -Path $exportPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'DatabaseName',
                'SqlHandle',
                'CreationTime',
                'LastExecutionTime',
                'OutputFile'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the expected additional properties available" {
            $additionalProps = @(
                'PlanHandle',
                'QueryPosition',
                'SingleStatementPlan',
                'BatchQueryPlan',
                'SingleStatementPlanRaw',
                'BatchQueryPlanRaw'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $additionalProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be accessible"
            }
        }

        It "Creates valid .sqlplan files" {
            $result[0].OutputFile | Should -Exist
            $result[0].OutputFile | Should -Match '\.sqlplan$'
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>