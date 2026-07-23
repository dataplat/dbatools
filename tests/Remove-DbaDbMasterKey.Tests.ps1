#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbMasterKey",
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
                "ExcludeDatabase",
                "All",
                "InputObject",
                "EnableException"
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
    # NOTE ON COVERAGE: two legs. The scope guard the source runs before resolving databases: when
    # -SqlInstance is supplied without -Database, -ExcludeDatabase, or -All, the command refuses to
    # proceed and returns (runs before any connection, probe-verified; WhatIf is belt-and-braces on
    # this destructive command though the guard returns ahead of any gated action). And the real
    # removal itself, exercised against a disposable database this suite creates, gives a master key,
    # then drops - so the DROP MASTER KEY path, the ShouldProcess gate, and the emitted result object
    # are all covered without ever touching a master key the suite does not own.
    Context "Guarding the database scope" {
        It "Warns once and returns nothing when SqlInstance is supplied without Database, ExcludeDatabase, or All" {
            $splatNoScope = @{
                SqlInstance     = $TestConfig.InstanceSingle
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Remove-DbaDbMasterKey @splatNoScope)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from the warning
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "You must specify Database, ExcludeDatabase or All when using SqlInstance"
        }
    }

    Context "Removing a real master key (live InstanceSingle)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $removeKeyPassword = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $removeKeyDb = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
            $null = $removeKeyDb | New-DbaDbMasterKey -SecurePassword $removeKeyPassword -Confirm:$false

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            if ($removeKeyDb) {
                $removeKeyDb | Remove-DbaDatabase -Confirm:$false
            }
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "drops the master key, reports it removed, and leaves none behind" {
            $result = Remove-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database $removeKeyDb.Name -Confirm:$false
            $result.Status | Should -Be "Master key removed"
            $result.Database | Should -Be $removeKeyDb.Name

            $afterKey = Get-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database $removeKeyDb.Name
            $afterKey | Should -BeNullOrEmpty
        }
    }
}