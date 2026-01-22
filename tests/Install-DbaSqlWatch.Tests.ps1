#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Install-DbaSqlWatch",
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
                "LocalFile",
                "Force",
                "PreRelease",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:($PSVersionTable.PSVersion.Major -gt 5 -or $env:appveyor) {
    # Skip IntegrationTests on AppVeyor because they take too long and skip on pwsh because the command is not supported.

    Context "Testing SqlWatch installer" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $database = "dbatoolsci_sqlwatch_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $server.Query("CREATE DATABASE $database")

            $results = Install-DbaSqlWatch -SqlInstance $TestConfig.InstanceSingle -Database $database

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Uninstall-DbaSqlWatch -SqlInstance $TestConfig.InstanceSingle -Database $database -ErrorAction SilentlyContinue
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $database -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Installs to specified database: $database" {
            $results[0].Database -eq $database | Should -Be $true
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $database = "dbatoolsci_sqlwatch_output_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $server.Query("CREATE DATABASE $database")

            $result = Install-DbaSqlWatch -SqlInstance $TestConfig.InstanceSingle -Database $database -EnableException

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Uninstall-DbaSqlWatch -SqlInstance $TestConfig.InstanceSingle -Database $database -ErrorAction SilentlyContinue
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $database -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Status",
                "DashboardPath"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }

        It "Has exactly the documented properties and no extras" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Status",
                "DashboardPath"
            )
            $actualProps = $result.PSObject.Properties.Name | Sort-Object
            $expectedProps = $expectedProps | Sort-Object
            Compare-Object -ReferenceObject $expectedProps -DifferenceObject $actualProps | Should -BeNullOrEmpty
        }
    }

    Context "Testing SqlWatch installer" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $database = "dbatoolsci_sqlwatch_install_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $server.Query("CREATE DATABASE $database")

            $results = Install-DbaSqlWatch -SqlInstance $TestConfig.InstanceSingle -Database $database

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Uninstall-DbaSqlWatch -SqlInstance $TestConfig.InstanceSingle -Database $database -ErrorAction SilentlyContinue
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $database -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Installs to specified database: $database" {
            $results[0].Database -eq $database | Should -Be $true
        }
        It "Installed tables" {
            $tableCount = (Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database $database | Where-Object Name -like "sqlwatch_*").Count
            $tableCount | Should -BeGreaterThan 0
        }
        It "Installed views" {
            $viewCount = (Get-DbaDbView -SqlInstance $TestConfig.InstanceSingle -Database $database | Where-Object Name -like "vw_sqlwatch_*").Count
            $viewCount | Should -BeGreaterThan 0
        }
        It "Installed stored procedures" {
            $sprocCount = (Get-DbaDbStoredProcedure -SqlInstance $TestConfig.InstanceSingle -Database $database | Where-Object Name -like "usp_sqlwatch_*").Count
            $sprocCount | Should -BeGreaterThan 0
        }
        It "Installed SQL Agent jobs" {
            $agentCount = (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle | Where-Object { ($PSItem.Name -like "SqlWatch-*") -or ($PSItem.Name -like "DBA-PERF-*") }).Count
            $agentCount | Should -BeGreaterThan 0
        }

    }
}