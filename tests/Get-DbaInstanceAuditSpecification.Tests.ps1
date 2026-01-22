#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaInstanceAuditSpecification",
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

    Context "Output Validation" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2 -MinimumVersion 10
            if ($server.ServerAuditSpecifications.Count -eq 0) {
                # Create a test audit and audit specification
                $auditName = "dbatoolsci_test_audit_$(Get-Random)"
                $specName = "dbatoolsci_test_spec_$(Get-Random)"
                $server.Audits.Add((New-Object Microsoft.SqlServer.Management.Smo.Audit($server, $auditName)))
                $server.Audits[$auditName].FilePath = $server.DefaultFile
                $server.Audits[$auditName].Create()
                $server.ServerAuditSpecifications.Add((New-Object Microsoft.SqlServer.Management.Smo.ServerAuditSpecification($server, $specName)))
                $server.ServerAuditSpecifications[$specName].AuditName = $auditName
                $server.ServerAuditSpecifications[$specName].Create()
            }
            $result = Get-DbaInstanceAuditSpecification -SqlInstance $TestConfig.instance2 -EnableException
        }

        AfterAll {
            if ($specName) {
                $server.ServerAuditSpecifications[$specName].Drop()
            }
            if ($auditName) {
                $server.Audits[$auditName].Drop()
            }
        }

        It "Returns the documented output type" {
            $result[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.ServerAuditSpecification]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'ID',
                'Name',
                'AuditName',
                'Enabled',
                'CreateDate',
                'DateLastModified',
                'Guid'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>