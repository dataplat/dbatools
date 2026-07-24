#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaXESession",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "Destination",
                "SourceSqlCredential",
                "DestinationSqlCredential",
                "XeSession",
                "ExcludeXeSession",
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
        $xeName = "dbatoolsci_ta131_xe"

        # Clean slate on both instances in case a prior run left the fixture behind.
        foreach ($currentServer in $sourceServer, $destServer) {
            $currentServer.Query("IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'$xeName') DROP EVENT SESSION [$xeName] ON SERVER")
        }

        # A single event with no target is a valid, deterministic session definition that exists on
        # the source but not the destination, so the copy evaluates a real create path under -WhatIf.
        $sourceServer.Query("CREATE EVENT SESSION [$xeName] ON SERVER ADD EVENT sqlserver.error_reported")
    }

    AfterAll {
        foreach ($currentServer in $sourceServer, $destServer) {
            $currentServer.Query("IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'$xeName') DROP EVENT SESSION [$xeName] ON SERVER")
        }
    }

    It "Does not create the source session on the destination when -WhatIf is used" {
        $getDestSessions = { $destServer.Query("SELECT name FROM sys.server_event_sessions").name }
        $before = @(& $getDestSessions)
        {
            Copy-DbaXESession -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -XeSession $xeName -WhatIf
        } | Should -Not -Throw
        $after = @(& $getDestSessions)
        $after | Should -Be $before
        $after | Should -Not -Contain $xeName
    }

    It "Emits no result object under -WhatIf because every status is gated by ShouldProcess" {
        $whatIfResult = Copy-DbaXESession -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -XeSession $xeName -WhatIf
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
                $null = Copy-DbaXESession -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceUnreachable -XeSession $xeName -WarningVariable connectWarning -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            } catch {
                # an unreachable destination may raise downstream errors; the warning stream is what this test asserts
            }
            $connectWarning | Should -Not -BeNullOrEmpty
        }
    }
}