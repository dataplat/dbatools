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
        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        $destServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -EnableException
        $auditName = "dbatoolsci_ta092_audit"

        # Clean slate on both instances in case a prior run left the fixture behind.
        foreach ($currentServer in $sourceServer, $destServer) {
            $currentServer.Audits.Refresh()
            $leftover = $currentServer.Audits[$auditName]
            if ($leftover) {
                try {
                    $leftover.Disable()
                    $leftover.Alter()
                } catch {
                    # a never-enabled audit cannot be disabled; drop it directly
                }
                $leftover.Drop()
            }
        }

        # APPLICATION_LOG target needs no file path, so the fixture is deterministic on any host.
        $sourceServer.Query("CREATE SERVER AUDIT [$auditName] TO APPLICATION_LOG")
        $sourceServer.Audits.Refresh()
    }

    AfterAll {
        foreach ($currentServer in $sourceServer, $destServer) {
            $currentServer.Audits.Refresh()
            $leftover = $currentServer.Audits[$auditName]
            if ($leftover) {
                try {
                    $leftover.Disable()
                    $leftover.Alter()
                } catch {
                    # a never-enabled audit cannot be disabled; drop it directly
                }
                $leftover.Drop()
            }
        }
    }

    It "Does not create the source audit on the destination when -WhatIf is used" {
        $destServer.Audits.Refresh()
        $before = @($destServer.Audits.Name)
        {
            Copy-DbaInstanceAudit -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Audit $auditName -WhatIf
        } | Should -Not -Throw
        $destServer.Audits.Refresh()
        $after = @($destServer.Audits.Name)
        $after | Should -Be $before
        $after | Should -Not -Contain $auditName
    }

    It "Emits no result object under -WhatIf because every status is gated by ShouldProcess" {
        $whatIfResult = Copy-DbaInstanceAudit -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Audit $auditName -WhatIf
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
                $null = Copy-DbaInstanceAudit -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceUnreachable -Audit $auditName -WarningVariable connectWarning -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            } catch {
                # an unreachable destination may raise downstream errors; the warning stream is what this test asserts
            }
            $connectWarning | Should -Not -BeNullOrEmpty
        }
    }
}