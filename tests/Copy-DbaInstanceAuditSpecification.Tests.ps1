#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaInstanceAuditSpecification",
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
                "AuditSpecification",
                "ExcludeAuditSpecification",
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

        $auditName = "dbatoolsci_auditspec_audit_$(Get-Random)"
        $auditSpecName = "dbatoolsci_auditspec_$(Get-Random)"
        $auditPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $auditPath -ItemType Directory

        # Use InstanceCopy2 as source (v15) and InstanceCopy1 as destination (v16)
        # to avoid version downgrade rejection
        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
        $destServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1

        # Create a server audit on both source and destination
        $createAuditSql = "CREATE SERVER AUDIT [$auditName] TO FILE (FILEPATH = N'$auditPath')"
        $sourceServer.Query($createAuditSql)
        $destServer.Query($createAuditSql)

        # Create audit specification on source only
        $createSpecSql = "CREATE SERVER AUDIT SPECIFICATION [$auditSpecName] FOR SERVER AUDIT [$auditName] ADD (FAILED_LOGIN_GROUP)"
        $sourceServer.Query($createSpecSql)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
        $destServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1

        # Clean up audit specifications and audits on both instances
        try { $sourceServer.Query("DROP SERVER AUDIT SPECIFICATION [$auditSpecName]") } catch { }
        try { $destServer.Query("DROP SERVER AUDIT SPECIFICATION [$auditSpecName]") } catch { }
        try { $sourceServer.Query("DROP SERVER AUDIT [$auditName]") } catch { }
        try { $destServer.Query("DROP SERVER AUDIT [$auditName]") } catch { }

        Remove-Item -Path $auditPath -Recurse -ErrorAction SilentlyContinue
    }

    Context "Output validation" {
        BeforeAll {
            $splatOutputTest = @{
                Source             = $TestConfig.InstanceCopy2
                Destination        = $TestConfig.InstanceCopy1
                AuditSpecification = $auditSpecName
            }
            $outputAll = @(Copy-DbaInstanceAuditSpecification @splatOutputTest)
            $result = $outputAll | Where-Object Name -eq $auditSpecName
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
            $result.Type | Should -Be "Server Audit Specification"
            $result.Name | Should -Be $auditSpecName
        }
    }
}