#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Compare-DbaAvailabilityGroup",
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
                "AvailabilityGroup",
                "Type",
                "ExcludeSystemJob",
                "ExcludeSystemLogin",
                "IncludeModifiedDate",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # Compare-DbaAvailabilityGroup is the umbrella command - it dispatches by -Type to the
    # Compare-DbaAgReplica{AgentJob,Login,Credential,Operator} sub-commands (default "All" runs all
    # four). Each sub-command carries the same pre-comparison guard. This block covers dispatch plus
    # that guard: a non-existent Availability Group warns once per selected -Type and emits nothing.
    # Dispatch against a live group is covered by the block further down.
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $isHadrEnabled = $server.IsHadrEnabled
        $random = Get-Random
        # the token the sub-commands interpolate into the guard message
        $instanceToken = "$([DbaInstanceParameter]$TestConfig.InstanceSingle)"
    }

    Context "Dispatch and guarding before the comparison" {
        It "Warns once and returns nothing for a single -Type when there is nothing to compare" {
            # -Type Login runs exactly one sub-command (Compare-DbaAgReplicaLogin), whose guard fires
            # on the standalone instance: one warning, no output.
            $splatSingle = @{
                SqlInstance       = $TestConfig.InstanceSingle
                AvailabilityGroup = "dbatoolsci_noag_$random"
                Type              = "Login"
                WarningVariable   = "warn"
                WarningAction     = "SilentlyContinue"
            }
            $result = @(Compare-DbaAvailabilityGroup @splatSingle)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            if ($isHadrEnabled) {
                $payload | Should -Be "No Availability Groups found on $instanceToken matching the specified criteria."
            } else {
                $payload | Should -Be "Availability Group (HADR) is not configured for the instance: $instanceToken."
            }
        }

        It "Fans out -Type All to all four sub-commands, warning once from each" {
            # The default -Type "All" dispatches to AgentJob, Login, Credential, and Operator, so on a
            # standalone instance the guard fires four times - one warning per sub-command, no output.
            $splatAll = @{
                SqlInstance       = $TestConfig.InstanceSingle
                AvailabilityGroup = "dbatoolsci_noag_$random"
                WarningVariable   = "warn"
                WarningAction     = "SilentlyContinue"
            }
            $result = @(Compare-DbaAvailabilityGroup @splatAll)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 4
            foreach ($record in $warn) {
                $payload = $record.Message -replace "^(\[[^\]]*\]\s*)+", ""
                if ($isHadrEnabled) {
                    $payload | Should -Be "No Availability Groups found on $instanceToken matching the specified criteria."
                } else {
                    $payload | Should -Be "Availability Group (HADR) is not configured for the instance: $instanceToken."
                }
            }
        }
    }
}

<#
    LIVE MULTI-REPLICA COVERAGE. Against a real >=2-replica Availability Group the dispatcher's job
    becomes observable: each -Type selects a sub-command whose rows carry a family-specific column
    (JobName, LoginName, CredentialName, OperatorName), so the output itself says which
    sub-commands ran. The AG topology is never touched; to keep every family's output non-empty
    regardless of how clean the lab happens to be, the suite plants one disposable dbatoolsci_
    object per family on a single replica and tears all four down by exact name.

    The last leg pipes two instance records through one invocation. The dispatcher REWRITES its own
    -Type parameter in the process block when the caller asks for "All", so a second record sees a
    $Type its caller never passed; that rewrite has to stay behaviour-preserving, and only a
    multi-record pipe can show it.
#>
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Discover a >=2-replica AG on any reachable HADR instance. The AG has no dedicated TestConfig
        # key (it is a persistent lab fixture), so resolve it dynamically. Every instance role is a
        # candidate, InstanceSingle included: whether a role is HADR-enabled and carries a
        # multi-replica group is a property of the lab, not of the role name.
        $agReady = $false
        $agSkipReason = $null
        $agInstance = $null
        $resolvedAg = $null

        # One disposable object per dispatched family, planted on a single replica so each
        # sub-command has a guaranteed difference to report. Torn down by exact name.
        $fixtureSuffix = Get-Random
        $fixtureJob = "dbatoolsci_agdispatchjob_$fixtureSuffix"
        $fixtureLogin = "dbatoolsci_agdispatchlogin_$fixtureSuffix"
        $fixtureCredential = "dbatoolsci_agdispatchcred_$fixtureSuffix"
        $fixtureOperator = "dbatoolsci_agdispatchop_$fixtureSuffix"
        $fixtureReplica = $null

        try {
            $candidates = @($TestConfig.InstanceSingle, $TestConfig.InstanceHadr, $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2) | Where-Object { $PSItem } | Select-Object -Unique
            foreach ($candidate in $candidates) {
                $candidateServer = Connect-DbaInstance -SqlInstance $candidate
                if (-not $candidateServer.IsHadrEnabled) {
                    continue
                }
                $multiReplicaAg = Get-DbaAvailabilityGroup -SqlInstance $candidateServer | Where-Object { $PSItem.AvailabilityReplicas.Count -ge 2 } | Select-Object -First 1
                if ($multiReplicaAg) {
                    $agInstance = $candidate
                    $resolvedAg = $multiReplicaAg.Name
                    $agReady = $true
                    break
                }
            }
            if (-not $agReady) {
                $agSkipReason = "no reachable instance hosts a >=2-replica availability group"
            }
        } catch {
            $agSkipReason = "availability-group discovery failed: $($PSItem.Exception.Message)"
        }

        if ($agReady) {
            # Assign the teardown target before the first create, so a throw part-way through still
            # reclaims whatever landed.
            $fixtureReplica = @($multiReplicaAg.AvailabilityReplicas.Name)[0]
            $fixtureSecret = ConvertTo-SecureString -String "dbatools.IO!$(Get-Random)" -AsPlainText -Force
            $null = New-DbaAgentJob -SqlInstance $fixtureReplica -Job $fixtureJob
            $null = New-DbaLogin -SqlInstance $fixtureReplica -Login $fixtureLogin -SecurePassword $fixtureSecret
            $splatNewCredential = @{
                SqlInstance    = $fixtureReplica
                Name           = $fixtureCredential
                Identity       = "dbatoolsci\$fixtureCredential"
                SecurePassword = $fixtureSecret
            }
            $null = New-DbaCredential @splatNewCredential
            $null = New-DbaAgentOperator -SqlInstance $fixtureReplica -Operator $fixtureOperator -EmailAddress "dispatch@dbatools.io"
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        if ($fixtureReplica) {
            $null = Remove-DbaAgentJob -SqlInstance $fixtureReplica -Job $fixtureJob -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $null = Remove-DbaLogin -SqlInstance $fixtureReplica -Login $fixtureLogin -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $null = Remove-DbaCredential -SqlInstance $fixtureReplica -Credential $fixtureCredential -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $null = Remove-DbaAgentOperator -SqlInstance $fixtureReplica -Operator $fixtureOperator -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        }
    }

    Context "Dispatching against a multi-replica availability group (read-only)" {
        It "Emits only login rows for -Type Login" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because $agSkipReason
                return
            }
            $rows = @(Compare-DbaAvailabilityGroup -SqlInstance $agInstance -AvailabilityGroup $resolvedAg -Type Login -WarningAction SilentlyContinue)
            $rows.Count | Should -BeGreaterThan 0
            foreach ($row in $rows) {
                $row.PSObject.Properties.Name | Should -Contain "LoginName"
                $row.PSObject.Properties.Name | Should -Not -Contain "JobName"
                $row.PSObject.Properties.Name | Should -Not -Contain "CredentialName"
                $row.PSObject.Properties.Name | Should -Not -Contain "OperatorName"
                $row.AvailabilityGroup | Should -Be $resolvedAg
            }
        }

        It "Emits only the selected families for a multi-valued -Type" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because $agSkipReason
                return
            }
            # Two of the four sub-commands, so the two unselected discriminator columns must be
            # absent from every row while both selected ones are represented.
            $rows = @(Compare-DbaAvailabilityGroup -SqlInstance $agInstance -AvailabilityGroup $resolvedAg -Type AgentJob, Operator -WarningAction SilentlyContinue)
            $rows.Count | Should -BeGreaterThan 0
            @($rows | Where-Object { $PSItem.PSObject.Properties.Name -contains "JobName" }).Count | Should -BeGreaterThan 0
            @($rows | Where-Object { $PSItem.PSObject.Properties.Name -contains "OperatorName" }).Count | Should -BeGreaterThan 0
            @($rows | Where-Object { $PSItem.PSObject.Properties.Name -contains "LoginName" }).Count | Should -Be 0
            @($rows | Where-Object { $PSItem.PSObject.Properties.Name -contains "CredentialName" }).Count | Should -Be 0
        }

        It "Fans out to all four sub-commands by default" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because $agSkipReason
                return
            }
            # The default -Type "All" is rewritten into the four family names, and on a live AG that
            # rewrite is visible as output from every one of them.
            $rows = @(Compare-DbaAvailabilityGroup -SqlInstance $agInstance -AvailabilityGroup $resolvedAg -WarningAction SilentlyContinue)
            foreach ($discriminator in @("JobName", "LoginName", "CredentialName", "OperatorName")) {
                @($rows | Where-Object { $PSItem.PSObject.Properties.Name -contains $discriminator }).Count | Should -BeGreaterThan 0
            }
        }

        It "Fans out for every piped record, not just the first" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because $agSkipReason
                return
            }
            # Same instance twice down the pipeline. The process block replaces "All" with the four
            # family names on the first record; if that rewrite leaked across records in a way that
            # changed the selection, the second record would contribute a different set - or nothing.
            $single = @(Compare-DbaAvailabilityGroup -SqlInstance $agInstance -AvailabilityGroup $resolvedAg -WarningAction SilentlyContinue)
            $double = @(@($agInstance, $agInstance) | Compare-DbaAvailabilityGroup -AvailabilityGroup $resolvedAg -WarningAction SilentlyContinue)

            $single.Count | Should -BeGreaterThan 0
            $double.Count | Should -Be (2 * $single.Count)
            foreach ($discriminator in @("JobName", "LoginName", "CredentialName", "OperatorName")) {
                @($double | Where-Object { $PSItem.PSObject.Properties.Name -contains $discriminator }).Count | Should -Be (2 * @($single | Where-Object { $PSItem.PSObject.Properties.Name -contains $discriminator }).Count)
            }
        }
    }
}
