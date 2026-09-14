#Requires -Module @{ ModuleName = "Pester"; ModuleVersion = "5.0" }
<#
    Regression coverage for the Azure log shipping blob name collision reported
    in https://github.com/dataplat/dbatools/issues/10667.

    Two concurrent CI runs that reach Invoke-DbaDbLogShipping within the same
    wall-clock second used to write the same FullBackup_PreLogShipping blob to
    the shared Azure container, because:

      1. The production timestamp was built with Get-Date -Format "yyyyMMddHHmmss"
         (second resolution).
      2. The CI test pinned the database names ("dbatoolsci_logship_azure" and
         "dbatoolsci_logship_addsecondary"), so the per-second collision was not
         bounded to a single runner.

    The Azure test path needs a real SQL Server plus a real Azure container, so
    the actual collision cannot be reproduced in a unit environment. The
    regression is therefore asserted on the shape of the inputs that drive the
    blob name: sub-second timestamp precision in the production cmdlet, and
    per-run unique database names in the CI script.
#>
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbLogShipping",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "$CommandName - Azure blob name collision (#10667)" -Tag UnitTests {
    BeforeAll {
        $RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
        $ProductionFile   = Join-Path $RepoRoot "public/Invoke-DbaDbLogShipping.ps1"
        $CiTestScriptFile = Join-Path $RepoRoot ".github/scripts/gh-actions.ps1"
    }

    Context "Production timestamp must include sub-second precision" {
        It "uses a millisecond format specifier for the Azure pre-log-shipping timestamp" {
            $ProductionFile | Should -Exist

            $productionContent = Get-Content -Path $ProductionFile -Raw

            # The offending line built the timestamp with second resolution only.
            # It must contain the millisecond 'fff' format specifier so two
            # callers that enter the cmdlet inside the same second no longer
            # produce the same Azure blob name.
            $timestampMatches = [regex]::Matches(
                $productionContent,
                'Get-Date\s+(?:-Format|-format)\s+"(?<fmt>[^"]+)"'
            )
            $azureTimestampLine = $timestampMatches | Where-Object {
                $PSItem.Groups['fmt'].Value -like '*yyyyMMddHHmmss*' -and
                $PSItem.Groups['fmt'].Value -like '*fff*'
            } | Select-Object -First 1

            $timestampReason = "Invoke-DbaDbLogShipping must build the Azure pre-log-shipping timestamp with sub-second precision to avoid the collision in #10667"
            $azureTimestampLine | Should -Not -BeNullOrEmpty -Because $timestampReason
        }
    }

    Context "CI test database names must be unique per run" {
        It "scopes every log shipping database name with GITHUB_RUN_ID" {
            $CiTestScriptFile | Should -Exist

            $ciScriptContent = Get-Content -Path $CiTestScriptFile -Raw

            # Every log shipping database name in the CI script must include a
            # per-run token (GITHUB_RUN_ID, plus GITHUB_RUN_ATTEMPT for reruns)
            # so two simultaneous CI jobs never collide on the shared Azure
            # container. This covers both "dbatoolsci_logship_azure" and
            # "dbatoolsci_logship_addsecondary".
            $dbNameMatches = [regex]::Matches(
                $ciScriptContent,
                '\$dbName\s*=\s*"(?<value>dbatoolsci_logship_[^"]+)"'
            )
            $dbNameMatches | Should -Not -BeNullOrEmpty -Because "the Azure log shipping integration tests must declare per-run database names"

            foreach ($dbNameMatch in $dbNameMatches) {
                $dbNameReason = "the database name used by the Azure log shipping tests must be unique per CI run (found: $($dbNameMatch.Groups['value'].Value))"
                $dbNameMatch.Groups['value'].Value | Should -Match 'GITHUB_RUN_ID' -Because $dbNameReason
            }
        }
    }
}
