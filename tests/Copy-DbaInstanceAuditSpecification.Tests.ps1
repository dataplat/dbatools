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
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Set variables. They are available in all the It blocks.
        $auditName = "dbatoolsci_ServerAudit_$(Get-Random)"
        $auditSpecName = "dbatoolsci_AuditSpec_$(Get-Random)"

        # Create a server audit on the source instance
        $createAuditSql = "CREATE SERVER AUDIT [$auditName] TO APPLICATION_LOG WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE)"
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query $createAuditSql

        # Create a server audit specification on the source instance
        $createSpecSql = "CREATE SERVER AUDIT SPECIFICATION [$auditSpecName] FOR SERVER AUDIT [$auditName] ADD (FAILED_LOGIN_GROUP) WITH (STATE = OFF)"
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query $createSpecSql

        # Create the same server audit on the destination so the copy can succeed
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query $createAuditSql

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects on both instances (order matters: spec before audit).
        $dropSpecSql = "IF EXISTS (SELECT 1 FROM sys.server_audit_specifications WHERE name = '$auditSpecName') DROP SERVER AUDIT SPECIFICATION [$auditSpecName]"
        $dropAuditSql = "IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = '$auditName') BEGIN ALTER SERVER AUDIT [$auditName] WITH (STATE = OFF); DROP SERVER AUDIT [$auditName] END"

        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query $dropSpecSql -ErrorAction SilentlyContinue
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query $dropAuditSql -ErrorAction SilentlyContinue
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query $dropSpecSql -ErrorAction SilentlyContinue
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query $dropAuditSql -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying audit specifications between instances" {
        It "Successfully copies a server audit specification" {
            $splatCopy = @{
                Source              = $TestConfig.InstanceCopy1
                Destination         = $TestConfig.InstanceCopy2
                AuditSpecification  = $auditSpecName
            }
            $results = Copy-DbaInstanceAuditSpecification @splatCopy -OutVariable "global:dbatoolsciOutput"
            $results.Name | Should -Be $auditSpecName
            $results.Status | Should -Be "Successful"
            $results.Type | Should -Be "Server Audit Specification"
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outputItem = ($global:dbatoolsciOutput | Where-Object { $null -ne $PSItem })[0]
        }

        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $outputItem | Should -BeOfType [PSCustomObject]
        }

        It "Should have the custom dbatools type name" {
            $outputItem.PSObject.TypeNames[0] | Should -Be "dbatools.MigrationObject"
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "DateTime",
                "SourceServer",
                "DestinationServer",
                "Name",
                "Type",
                "Status",
                "Notes"
            )
            $defaultColumns = $outputItem.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "MigrationObject"
        }
    }
}