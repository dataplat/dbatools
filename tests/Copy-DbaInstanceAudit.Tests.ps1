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
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # The audit is never enabled, so it writes no file into the temp folder
        $auditName = "dbatoolsci_audit_$(Get-Random)"
        $auditSpecName = "dbatoolsci_auditspec_$(Get-Random)"
        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $destServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
        $null = $sourceServer.Query("CREATE SERVER AUDIT [$auditName] TO FILE (FILEPATH = N'$($TestConfig.Temp)') WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE)")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $cleanupSql = @"
IF EXISTS (SELECT 1 FROM sys.server_audit_specifications WHERE name = N'$auditSpecName')
BEGIN
    ALTER SERVER AUDIT SPECIFICATION [$auditSpecName] WITH (STATE = OFF);
    DROP SERVER AUDIT SPECIFICATION [$auditSpecName];
END
IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'$auditName')
    DROP SERVER AUDIT [$auditName];
"@
        $null = $sourceServer.Query($cleanupSql)
        $null = $destServer.Query($cleanupSql)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying a server audit" {
        BeforeAll {
            $splatCopyAudit = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Audit       = $auditName
            }
            $results = Copy-DbaInstanceAudit @splatCopyAudit
        }

        It "Returns one successful result" {
            # Counts the output itself, $results.Status.Count would skip a $null written by the command
            @($results).Count | Should -Be 1
            $results.Name | Should -Be $auditName
            $results.Status | Should -Be "Successful"
        }

        It "Creates the audit on the destination" {
            $destServer.Audits.Refresh()
            $destServer.Audits[$auditName] | Should -Not -BeNullOrEmpty
        }
    }

    Context "When the audit exists on the destination" {
        It "Reports the audit as skipped" {
            $splatCopyExisting = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Audit       = $auditName
            }
            $results = Copy-DbaInstanceAudit @splatCopyExisting
            @($results).Count | Should -Be 1
            $results.Status | Should -Be "Skipped"
            $results.Notes | Should -Be "Already exists on destination"
        }
    }

    Context "When the audit exists on the destination with a specification and -Force is used" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # An enabled specification that uses the audit has to be dropped before the audit can be replaced
            $null = $destServer.Query("CREATE SERVER AUDIT SPECIFICATION [$auditSpecName] FOR SERVER AUDIT [$auditName] ADD (FAILED_LOGIN_GROUP) WITH (STATE = ON)")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $splatCopyForce = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Audit       = $auditName
                Force       = $true
            }
            $forceResults = Copy-DbaInstanceAudit @splatCopyForce
        }

        It "Replaces the audit" {
            @($forceResults).Count | Should -Be 1
            $forceResults.Status | Should -Be "Successful"
        }

        It "Drops the specification that used the audit" {
            $destServer.ServerAuditSpecifications.Refresh()
            $destServer.ServerAuditSpecifications[$auditSpecName] | Should -BeNullOrEmpty
        }
    }
}