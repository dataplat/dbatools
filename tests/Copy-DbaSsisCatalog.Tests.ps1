#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaSsisCatalog",
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
                "Project",
                "Folder",
                "Environment",
                "CreateCatalogPassword",
                "EnableSqlClr",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: copying an SSIS catalog needs the IntegrationServices SMO object model plus a live
    # Source+Destination pair with a running SSIS service, all Windows-PowerShell-only and absent from the gate
    # host, so the live copy is deferred. What IS deterministic on both editions is the pre-copy refusal the
    # source runs before it deploys anything: on PowerShell Core the command refuses outright ("This command is
    # not supported on Linux or macOS"), and on Windows PowerShell the source-connection failure returns nothing
    # with a friendly warning. The source connection is mocked so the Desktop leg is deterministic and needs no
    # reachable endpoint. Both branches return zero objects and one warning, so this leg runs on both gate
    # editions with zero skips and asserts the edition-appropriate message.
    Context "Refuses before copying anything" {
        It "warns and copies nothing when the source cannot be reached" {
            Mock -CommandName Connect-DbaInstance -ModuleName dbatools -MockWith {
                throw "simulated: source instance unreachable"
            }

            $splatRefuse = @{
                Source          = "dbatoolsci-mock-src"
                Destination     = "dbatoolsci-mock-dst"
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = @(Copy-DbaSsisCatalog @splatRefuse)
            $result.Count | Should -Be 0
            $warn.Count | Should -BeGreaterThan 0

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            if ($PSVersionTable.PSEdition -eq "Core") {
                $payload | Should -Be "This command is not supported on Linux or macOS"
            } else {
                $payload | Should -BeLike "Error occurred while establishing connection to *"
            }
        }
    }
}
