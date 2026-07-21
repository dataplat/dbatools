#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaAgSpn",
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
                "Credential",
                "AvailabilityGroup",
                "Listener",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: the guard legs below (no-input, absent-AG) are connection-independent or
    # standalone-safe. The live listener walk needs an Availability Group WITH a configured
    # listener; a prior revision of this row recorded that as DEFERRED-TO-AG01, but that was wrong
    # - InstanceSingle is HADR-enabled and carries AG01 with listener AG01-Listener, so the live
    # leg is characterized here rather than deferred (same correction applied to TA-085). The
    # listener legs discover their fixture from the instance and skip explicitly if no AG on this
    # instance has a listener, so they stay honest on a lab that lacks one. This command is
    # read-only ([CmdletBinding()] with no SupportsShouldProcess), so no WhatIf is passed.
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $isHadrEnabled = $server.IsHadrEnabled
        $instanceToken = "$([DbaInstanceParameter]$TestConfig.InstanceSingle)"
        $random = Get-Random

        # Discover an AG that actually has a listener; the expected SPNs are DERIVED from the
        # server and listener objects the same way the command derives them, so these assertions
        # hold on any lab rather than pinning this one's names.
        $listenerAg = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceSingle |
            Where-Object { @($PSItem | Get-DbaAgListener).Count -gt 0 } |
            Select-Object -First 1

        if ($listenerAg) {
            $agListener = @($listenerAg | Get-DbaAgListener)[0]
            $dnsName = (($server.Information.FullyQualifiedNetName -split "\.") | Select-Object -Skip 1) -join "."
            $hostEntry = $agListener.Name, $dnsName -join "."
            $listenerPort = $agListener.PortNumber

            if ($agListener.InstanceName -eq "MSSQLSERVER") {
                $expectedBareSpn = "MSSQLSvc/$hostEntry"
            } else {
                $expectedBareSpn = "MSSQLSvc/" + $hostEntry + ":" + $agListener.InstanceName
            }
            $expectedPortSpn = "MSSQLSvc/$hostEntry" + ":" + $listenerPort
        }
    }

    Context "Guarding before the SPN test" {
        It "Warns once and returns nothing when neither SqlInstance nor InputObject is supplied" {
            $splatNoInput = @{
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = @(Test-DbaAgSpn @splatNoInput)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from the warning
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "You must supply either -SqlInstance or an Input Object"
        }

        It "Tests nothing when the requested Availability Group does not exist" {
            $splatAbsentAg = @{
                SqlInstance       = $TestConfig.InstanceSingle
                AvailabilityGroup = "dbatoolsci_noag_$random"
                WarningVariable   = "warn"
                WarningAction     = "SilentlyContinue"
            }
            $result = @(Test-DbaAgSpn @splatAbsentAg)
            $result.Count | Should -Be 0

            if ($isHadrEnabled) {
                # an HADR instance filters the absent name silently in Get-DbaAvailabilityGroup
                $warn.Count | Should -Be 0
            } else {
                # a non-HADR instance warns exactly once from the nested Get-DbaAvailabilityGroup
                $warn.Count | Should -Be 1
                $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
                $payload | Should -Be "Availability Group (HADR) is not configured for the instance: $instanceToken."
            }
        }
    }

    Context "Walking a live Availability Group listener" {
        It "Emits exactly two SPN objects per listener - one bare, one port-qualified" {
            if (-not $listenerAg) {
                Set-ItResult -Skipped -Because "no Availability Group on this instance has a listener"
                return
            }

            $result = @($listenerAg | Test-DbaAgSpn)
            $result.Count | Should -Be 2
            $result.RequiredSPN | Should -Contain $expectedBareSpn
            $result.RequiredSPN | Should -Contain $expectedPortSpn
        }

        It "Carries the documented SPN result shape" {
            if (-not $listenerAg) {
                Set-ItResult -Skipped -Because "no Availability Group on this instance has a listener"
                return
            }

            $spn = @($listenerAg | Test-DbaAgSpn)[0]
            $expectedProperties = @(
                "ComputerName",
                "SqlInstance",
                "InstanceName",
                "SqlProduct",
                "InstanceServiceAccount",
                "RequiredSPN",
                "IsSet",
                "Cluster",
                "TcpEnabled",
                "Port",
                "DynamicPort",
                "Warning",
                "Error"
            )
            foreach ($propertyName in $expectedProperties) {
                $spn.PSObject.Properties.Name | Should -Contain $propertyName
            }

            # TcpEnabled/DynamicPort are hardcoded for listeners by the source (:153,:155), and the
            # port is the listener's own. IsSet is environmental (depends on real AD registration)
            # so it is pinned only as a boolean, not to a value.
            $spn.TcpEnabled | Should -BeTrue
            $spn.DynamicPort | Should -BeFalse
            $spn.Port | Should -Be $listenerPort
            $spn.IsSet | Should -BeOfType [bool]

            # Error tracks IsSet: "SPN missing" when unregistered, "None" when set (:222-224).
            if ($spn.IsSet) {
                $spn.Error | Should -Be "None"
            } else {
                $spn.Error | Should -Be "SPN missing"
            }
        }

        It "Returns nothing when -Listener matches no listener on the group" {
            if (-not $listenerAg) {
                Set-ItResult -Skipped -Because "no Availability Group on this instance has a listener"
                return
            }

            $result = @($listenerAg | Test-DbaAgSpn -Listener "dbatoolsci_nolistener_$random")
            $result.Count | Should -Be 0
        }

        It "CHARACTERIZATION: re-emits earlier records' SPNs on every later pipeline record" {
            if (-not $listenerAg) {
                Set-ItResult -Skipped -Because "no Availability Group on this instance has a listener"
                return
            }

            # DO NOT FIX in the port - this pins a latent SOURCE bug that the C# transplant
            # preserves deliberately. $spns is initialized in begin{} (:106) but the emit loop
            # `foreach ($spn in $spns)` (:180) lives in process{}, so the accumulator is never
            # reset per record: record 1 emits its 2 SPNs, record 2 walks the FULL accumulated set
            # and emits 4 (its own 2 plus record 1's 2 again). Two records therefore yield 6
            # objects, not 4. This is the cross-record leg that makes the whole-record hop's carry
            # observable - without it a green gate proves nothing about the carry.
            $result = @($listenerAg, $listenerAg | Test-DbaAgSpn)
            $result.Count | Should -Be 6

            # and the duplication is of the SAME listener's pair, not distinct data
            @($result | Where-Object { $PSItem.RequiredSPN -eq $expectedBareSpn }).Count | Should -Be 3
            @($result | Where-Object { $PSItem.RequiredSPN -eq $expectedPortSpn }).Count | Should -Be 3
        }
    }
}
