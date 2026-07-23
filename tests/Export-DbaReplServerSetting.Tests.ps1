#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaReplServerSetting",
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
                "Path",
                "FilePath",
                "ScriptOption",
                "InputObject",
                "Encoding",
                "Passthru",
                "NoClobber",
                "Append",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: scripting out a live replication topology requires the native RMO
    # replication libraries and a configured distributor/publications - that end-to-end
    # .Script() + file-write leg is DEFERRED to the GitHub Actions replication harness
    # (gh-actions-repl-*), which is where the libraries load. What IS characterizable on a plain
    # instance is the read path of the port: the begin block loads (or, where the libraries are
    # absent, warns that it cannot load) the replication libraries, connects via Get-DbaReplServer,
    # and - with no replication server object to script - returns nothing without throwing. That
    # single leg exercises the module hop, the begin-block library load, the live connection, and
    # the empty-input process loop end to end.
    Context "Reading an instance with no scriptable replication server" {
        It "Returns nothing and does not throw" {
            $splatExport = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Passthru        = $true
                WarningVariable = "replWarn"
                WarningAction   = "SilentlyContinue"
                ErrorAction     = "SilentlyContinue"
            }
            $result = Export-DbaReplServerSetting @splatExport
            $result | Should -BeNullOrEmpty
            ($replWarn -join "`n") | Should -Match "replication librar"
        }
    }
}