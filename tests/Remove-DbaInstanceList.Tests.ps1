#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaInstanceList",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Register",
                "Scope"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # Fixture hygiene (lane-D scrub caveat, coordinator 22:30 ruling): the persisted
        # TabExpansion.KnownInstances store self-perpetuates corruption from historical red
        # runs across processes - start every run from a clean, correctly-typed store so a
        # red here always means THIS build, never inherited junk.
        Set-DbatoolsConfig -FullName TabExpansion.KnownInstances -Value @([string[]]@())
        Register-DbatoolsConfig -FullName TabExpansion.KnownInstances

        $instanceName = "dbatoolsci_testinstance_$(Get-Random)"
        Add-DbaInstanceList -SqlInstance $instanceName
    }

    Context "removes instances from the list" {
        It "removes an instance without error" {
            { Remove-DbaInstanceList -SqlInstance $instanceName } | Should -Not -Throw
        }

        It "instance no longer appears in Get-DbaInstanceList after removal" {
            $result = Get-DbaInstanceList
            $result | Should -Not -Contain $instanceName.ToLowerInvariant()
        }

        It "instance no longer appears in the TEPP cache after removal" {
            $cache = [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"]
            $cache | Should -Not -Contain $instanceName.ToLowerInvariant()
        }
    }
}
