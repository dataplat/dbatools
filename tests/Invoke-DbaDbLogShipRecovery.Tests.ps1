#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbLogShipRecovery",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Database",
                "SqlCredential",
                "NoRecovery",
                "EnableException",
                "Force",
                "InputObject",
                "Delay"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: an actual recovery requires a database that is a live log shipping
    # secondary (copy/restore agent jobs wired to it), which the standalone InstanceSingle does
    # not provide - that leg is DEFERRED-TO-GATE on the lab log shipping fixture. What IS
    # characterizable here is the guard chain that runs BEFORE any recovery action: the
    # no-Database/no-Force parameter guard (fires per instance before any connection), the silent
    # resolution of a nonexistent database name, and the not-a-log-shipping-secondary guard,
    # which branches on the Agent-running state the source probes first. The output object is
    # emitted per log shipping row only, so every guard leg emits nothing. Every call below also
    # passes WhatIf as belt-and-braces: the guards are plain warnings and reads that fire either
    # way, and a surprise log shipping secondary still could not be recovered by this test.
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $masterDb = Get-DbaDatabase -SqlInstance $server -Database master
        $random = Get-Random
        # probe Agent state exactly as the source does, so the expected guard branches with the
        # environment instead of assuming it; [char]39 supplies the single quotes the LIKE
        # pattern needs without putting forbidden single quotes in the test source
        $q = [char]39
        $agentQuery = "SELECT COUNT(*) AS AgentCount FROM master.dbo.sysprocesses WITH (NOLOCK) WHERE program_name LIKE ${q}SQLAgent%${q}"
        $agentRunning = ($server.Query($agentQuery)).AgentCount -ge 1
    }

    Context "Guarding before the recovery" {
        It "Stays fully silent when neither SqlInstance nor InputObject is supplied" {
            $splatNoInput = @{
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Invoke-DbaDbLogShipRecovery @splatNoInput)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 0
        }

        It "Warns once and returns nothing when SqlInstance is supplied without Database or Force" {
            $splatNoDatabase = @{
                SqlInstance     = $TestConfig.InstanceSingle
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Invoke-DbaDbLogShipRecovery @splatNoDatabase)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from the warning
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "You must specify a -Database or -Force for all databases"
        }

        It "Stays fully silent when the requested database does not exist" {
            # database resolution rides Get-DbaDatabase, which filters a non-matching name
            # silently - no databases resolve, the per-database loop never runs
            $splatAbsentDb = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = "dbatoolsci_nodb_$random"
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Invoke-DbaDbLogShipRecovery @splatAbsentDb)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 0
        }

        It "Warns once and returns nothing when the database is not a log shipping secondary" {
            # master exists on every instance and can never be a log shipping secondary, so the
            # guard chain is structurally guaranteed: Agent running reaches the log shipping
            # lookup and warns not-configured; Agent stopped warns at the earlier Agent guard
            $splatMaster = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = "master"
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Invoke-DbaDbLogShipRecovery @splatMaster)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            if ($agentRunning) {
                # the source interpolates the SMO Database object into the message; reproducing
                # the same interpolation from the fetched object pins the same rendering
                $payload | Should -Be "The database $masterDb is not configured as a secondary database for log shipping."
            } else {
                $payload | Should -Be "The agent service is not in a running state. Please start the service."
            }
        }
    }
}
