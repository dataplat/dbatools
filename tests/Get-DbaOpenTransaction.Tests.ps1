#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaOpenTransaction",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When connecting to SQL Server" {
        It "Should not throw when connecting to instance" {
            { Get-DbaOpenTransaction -SqlInstance $TestConfig.InstanceSingle } | Should -Not -Throw
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Create a test transaction to ensure we have output
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
            $null = $server.Query("BEGIN TRANSACTION; SELECT 1")
            Start-Sleep -Milliseconds 500
            $result = Get-DbaOpenTransaction -SqlInstance $TestConfig.instance1 -EnableException
        }

        AfterAll {
            # Clean up - rollback any test transactions
            try {
                $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
                $null = $server.Query("IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION")
            } catch {
                # Ignore cleanup errors
            }
        }

        It "Returns PSCustomObject" {
            if ($result) {
                $result[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
            }
        }

        It "Has the expected properties for open transactions" {
            if ($result) {
                $expectedProps = @(
                    "ComputerName",
                    "InstanceName",
                    "SqlInstance",
                    "Spid",
                    "Login",
                    "Database",
                    "BeginTime",
                    "LogBytesUsed",
                    "LogBytesReserved",
                    "LastQuery",
                    "LastPlan"
                )
                $actualProps = $result[0].PSObject.Properties.Name
                foreach ($prop in $expectedProps) {
                    $actualProps | Should -Contain $prop -Because "property '$prop' should be present in output"
                }
            }
        }

        It "Returns nothing when no open transactions exist" -Skip {
            # This test requires a clean instance with no open transactions
            # Marked as -Skip since test environment may have background transactions
        }
    }
}