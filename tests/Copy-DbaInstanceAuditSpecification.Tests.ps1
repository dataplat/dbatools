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

        # The specification needs its audit on both instances. The audit is never enabled, so it writes no file into the temp folder.
        $auditName = "dbatoolsci_audit_$(Get-Random)"
        $auditSpecName = "dbatoolsci_auditspec_$(Get-Random)"
        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $destServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
        $createAuditSql = "CREATE SERVER AUDIT [$auditName] TO FILE (FILEPATH = N'$($TestConfig.Temp)') WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE)"
        $null = $sourceServer.Query($createAuditSql)
        $null = $destServer.Query($createAuditSql)
        $null = $sourceServer.Query("CREATE SERVER AUDIT SPECIFICATION [$auditSpecName] FOR SERVER AUDIT [$auditName] ADD (FAILED_LOGIN_GROUP)")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $cleanupSql = @"
IF EXISTS (SELECT 1 FROM sys.server_audit_specifications WHERE name = N'$auditSpecName')
    DROP SERVER AUDIT SPECIFICATION [$auditSpecName];
IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'$auditName')
    DROP SERVER AUDIT [$auditName];
"@
        $null = $sourceServer.Query($cleanupSql)
        $null = $destServer.Query($cleanupSql)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying a server audit specification" {
        BeforeAll {
            $splatCopySpec = @{
                Source             = $TestConfig.InstanceCopy1
                Destination        = $TestConfig.InstanceCopy2
                AuditSpecification = $auditSpecName
            }
            $results = Copy-DbaInstanceAuditSpecification @splatCopySpec
        }

        It "Returns one successful result" {
            # Counts the output itself, $results.Status.Count would skip a $null written by the command
            @($results).Count | Should -Be 1
            $results.Name | Should -Be $auditSpecName
            $results.Status | Should -Be "Successful"
        }

        It "Creates the specification on the destination" {
            $destServer.ServerAuditSpecifications.Refresh()
            $destServer.ServerAuditSpecifications[$auditSpecName].AuditName | Should -Be $auditName
        }
    }
}