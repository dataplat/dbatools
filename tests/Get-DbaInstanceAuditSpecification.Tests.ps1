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
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $auditName = "dbatoolsci_audit_$(Get-Random)"
        $auditSpecName = "dbatoolsci_auditspec_$(Get-Random)"
        $auditPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $auditPath -ItemType Directory

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $server.Query("CREATE SERVER AUDIT [$auditName] TO FILE (FILEPATH = N'$auditPath')")
        $server.Query("CREATE SERVER AUDIT SPECIFICATION [$auditSpecName] FOR SERVER AUDIT [$auditName] ADD (FAILED_LOGIN_GROUP)")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        try { $server.Query("DROP SERVER AUDIT SPECIFICATION [$auditSpecName]") } catch { }
        try { $server.Query("DROP SERVER AUDIT [$auditName]") } catch { }

        Remove-Item -Path $auditPath -Recurse -ErrorAction SilentlyContinue
    }

    Context "Output validation" {
        BeforeAll {
            $result = @(Get-DbaInstanceAuditSpecification -SqlInstance $TestConfig.InstanceSingle)
            $auditSpecResult = $result | Where-Object Name -eq $auditSpecName
        }

        It "Returns output of the documented type" {
            $auditSpecResult | Should -Not -BeNullOrEmpty
            $auditSpecResult[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.ServerAuditSpecification"
        }

        It "Has the expected default display properties" {
            $defaultProps = $auditSpecResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "ID", "Name", "AuditName", "Enabled", "CreateDate", "DateLastModified", "Guid")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Returns the correct audit specification values" {
            $auditSpecResult[0].Name | Should -Be $auditSpecName
            $auditSpecResult[0].AuditName | Should -Be $auditName
        }
    }
}