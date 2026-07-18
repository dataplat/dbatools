#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Update-DbaMaintenanceSolution",
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
                "Database",
                "Solution",
                "LocalFile",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: installing or updating the Ola Hallengren maintenance solution writes
    # stored procedures into a target database and, without -WhatIf, refreshes a locally cached
    # copy of the software from the internet - the real install leg is DEFERRED-TO-GATE on a
    # maintenance-solution fixture. -SqlInstance is Mandatory and the command connects before the
    # database is resolved, so there is no connection-independent leg. What IS deterministic on any
    # reachable instance is the database-not-found guard: a nonexistent -Database warns once and
    # skips the instance without output. WhatIf is REQUIRED here, not just belt-and-braces: it
    # gates both the cached-copy refresh (so the test performs no download) and every install
    # write, while the not-found guard is a plain warning that fires regardless. The instance token
    # in the message is reproduced from the same [DbaInstance] coercion the source applies.
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $instanceToken = "$([DbaInstance]$TestConfig.InstanceSingle)"
        # a GUID guarantees a globally unique name so no pre-existing database can match and
        # silently defeat the not-found guard
        $dbName = "dbatoolsci_nodb_$([guid]::NewGuid())"
    }

    Context "Guarding a missing database" {
        It "Warns once and returns nothing when the requested database does not exist" {
            # precondition: the database must genuinely not exist for this to test the guard
            ($server.Databases | Where-Object Name -eq $dbName) | Should -BeNullOrEmpty

            $splatMissingDb = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $dbName
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Update-DbaMaintenanceSolution @splatMissingDb)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from the warning
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "Database $dbName not found on $instanceToken. Skipping."
        }
    }
}