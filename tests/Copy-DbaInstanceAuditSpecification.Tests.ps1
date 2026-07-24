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
        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        $destServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -EnableException
        $auditName = "dbatoolsci_ta093_audit"
        $specName = "dbatoolsci_ta093_spec"

        # Clean slate on both instances in case a prior run left the fixture behind. A specification
        # must be dropped before the audit it references, so the drop order is spec then audit.
        foreach ($currentServer in $sourceServer, $destServer) {
            $currentServer.ServerAuditSpecifications.Refresh()
            $leftoverSpec = $currentServer.ServerAuditSpecifications[$specName]
            if ($leftoverSpec) {
                try {
                    $leftoverSpec.Disable()
                } catch {
                    # a never-enabled specification cannot be disabled; drop it directly
                }
                $leftoverSpec.Drop()
            }
            $currentServer.Audits.Refresh()
            $leftoverAudit = $currentServer.Audits[$auditName]
            if ($leftoverAudit) {
                try {
                    $leftoverAudit.Disable()
                    $leftoverAudit.Alter()
                } catch {
                    # a never-enabled audit cannot be disabled; drop it directly
                }
                $leftoverAudit.Drop()
            }
        }

        # APPLICATION_LOG target needs no file path, so the fixture is deterministic on any host.
        # The specification references that audit; both must exist on the source for the copy to
        # evaluate a real specification.
        $sourceServer.Query("CREATE SERVER AUDIT [$auditName] TO APPLICATION_LOG")
        $sourceServer.Query("CREATE SERVER AUDIT SPECIFICATION [$specName] FOR SERVER AUDIT [$auditName] ADD (FAILED_LOGIN_GROUP)")
        $sourceServer.ServerAuditSpecifications.Refresh()
    }

    AfterAll {
        foreach ($currentServer in $sourceServer, $destServer) {
            $currentServer.ServerAuditSpecifications.Refresh()
            $leftoverSpec = $currentServer.ServerAuditSpecifications[$specName]
            if ($leftoverSpec) {
                try {
                    $leftoverSpec.Disable()
                } catch {
                    # a never-enabled specification cannot be disabled; drop it directly
                }
                $leftoverSpec.Drop()
            }
            $currentServer.Audits.Refresh()
            $leftoverAudit = $currentServer.Audits[$auditName]
            if ($leftoverAudit) {
                try {
                    $leftoverAudit.Disable()
                    $leftoverAudit.Alter()
                } catch {
                    # a never-enabled audit cannot be disabled; drop it directly
                }
                $leftoverAudit.Drop()
            }
        }
    }

    It "Does not create the source audit specification on the destination when -WhatIf is used" {
        $destServer.ServerAuditSpecifications.Refresh()
        $before = @($destServer.ServerAuditSpecifications.Name)
        {
            Copy-DbaInstanceAuditSpecification -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -AuditSpecification $specName -WhatIf
        } | Should -Not -Throw
        $destServer.ServerAuditSpecifications.Refresh()
        $after = @($destServer.ServerAuditSpecifications.Name)
        $after | Should -Be $before
        $after | Should -Not -Contain $specName
    }

    It "Emits no result object under -WhatIf because every status is gated by ShouldProcess" {
        $whatIfResult = Copy-DbaInstanceAuditSpecification -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -AuditSpecification $specName -WhatIf
        $whatIfResult | Should -BeNullOrEmpty
    }

    Context "Unreachable destination" {
        BeforeAll {
            # Scoped to this Context alone, never the whole file: the legs above make real
            # connections and would turn flaky on a slow guest under a 1-second fuse. The pin is
            # needed because the unreachable endpoint is only refused instantly where the port is
            # CLOSED - where it is firewalled the packet is dropped and the leg waits out the
            # 15-second default instead. Restoring in AfterAll is mandatory, the setting being
            # process-wide.
            $previousConnectTimeout = Get-DbatoolsConfigValue -FullName sql.connection.timeout
            Set-DbatoolsConfig -FullName sql.connection.timeout -Value 1
        }
        AfterAll {
            Set-DbatoolsConfig -FullName sql.connection.timeout -Value $previousConnectTimeout
        }

        It "Surfaces the destination-connect warning instead of throwing when the destination is unreachable" {
            $connectWarning = $null
            try {
                $null = Copy-DbaInstanceAuditSpecification -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceUnreachable -AuditSpecification $specName -WarningVariable connectWarning -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            } catch {
                # an unreachable destination may raise downstream errors; the warning stream is what this test asserts
            }
            $connectWarning | Should -Not -BeNullOrEmpty
        }
    }
}