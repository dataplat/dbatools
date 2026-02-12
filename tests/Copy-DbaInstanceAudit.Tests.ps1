#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaInstanceAudit",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Audit",
                "ExcludeAudit",
                "Path",
                "Force",
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
        $auditPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $auditPath -ItemType Directory

        # Create a test audit on the source instance
        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $createAuditSql = "CREATE SERVER AUDIT [$auditName] TO FILE (FILEPATH = N'$auditPath')"
        $sourceServer.Query($createAuditSql)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up the audit on both source and destination
        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $destServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2

        try { $sourceServer.Query("DROP SERVER AUDIT [$auditName]") } catch { }
        try { $destServer.Query("DROP SERVER AUDIT [$auditName]") } catch { }

        Remove-Item -Path $auditPath -Recurse -ErrorAction SilentlyContinue
    }

    Context "Output validation" {
        BeforeAll {
            $splatOutputTest = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Audit       = $auditName
            }
            $outputAll = @(Copy-DbaInstanceAudit @splatOutputTest)
            $result = $outputAll | Where-Object Name -eq $auditName
        }

        It "Returns output of the expected type" {
            $result | Should -Not -BeNullOrEmpty
            $result.psobject.TypeNames | Should -Contain "dbatools.MigrationObject"
        }

        It "Has the expected default display properties" {
            $defaultProps = $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Returns the correct migration object values" {
            $result.Type | Should -Be "Server Audit"
            $result.Name | Should -Be $auditName
        }
    }
}