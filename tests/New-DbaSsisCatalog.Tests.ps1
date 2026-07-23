#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaSsisCatalog",
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
                "SecurePassword",
                "SsisCatalog",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # COVERAGE NOTE: creating an SSIS Catalog needs the IntegrationServices SMO object model plus a running
    # SSIS service, both of which are Windows-PowerShell-only and absent from the gate host, so the live
    # Create path is deferred. What IS deterministic on both editions is the begin-block refusal the source
    # runs BEFORE any connection: PowerShell Core refuses outright ("This command is not supported on Linux
    # or macOS"), and Windows PowerShell refuses when neither a password nor a credential is supplied. Both
    # latch the interrupt in the begin scope and return without touching the instance, so this leg runs on
    # both gate editions and asserts the edition-appropriate message.
    Context "Refuses in the begin block without creating a catalog" {
        It "warns and creates nothing when no password or credential is supplied" {
            $splatNoPassword = @{
                SqlInstance     = $TestConfig.InstanceSingle
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = @(New-DbaSsisCatalog @splatNoPassword)
            $result.Count | Should -Be 0
            $warn.Count | Should -BeGreaterThan 0

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $expected = if ($PSVersionTable.PSEdition -eq "Core") {
                "This command is not supported on Linux or macOS"
            } else {
                "You must specify either -SecurePassword or -Credential"
            }
            $payload | Should -Be $expected
        }
    }
}