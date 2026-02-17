#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaScriptingOption",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Returns a ScriptingOptions object" {
        BeforeAll {
            $result = New-DbaScriptingOption -OutVariable "global:dbatoolsciOutput"
        }

        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return exactly one object" {
            $global:dbatoolsciOutput | Should -Not -BeNullOrEmpty
            @($global:dbatoolsciOutput).Count | Should -Be 1
        }

        It "Should return a Microsoft.SqlServer.Management.Smo.ScriptingOptions object" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.ScriptingOptions]
        }

        It "Should have a ScriptDrops property" {
            $global:dbatoolsciOutput[0].PSObject.Properties["ScriptDrops"] | Should -Not -BeNullOrEmpty
        }

        It "Should have a WithDependencies property" {
            $global:dbatoolsciOutput[0].PSObject.Properties["WithDependencies"] | Should -Not -BeNullOrEmpty
        }

        It "Should have an Indexes property" {
            $global:dbatoolsciOutput[0].PSObject.Properties["Indexes"] | Should -Not -BeNullOrEmpty
        }

        It "Should have a Triggers property" {
            $global:dbatoolsciOutput[0].PSObject.Properties["Triggers"] | Should -Not -BeNullOrEmpty
        }

        It "Should have a Permissions property" {
            $global:dbatoolsciOutput[0].PSObject.Properties["Permissions"] | Should -Not -BeNullOrEmpty
        }

        It "Should have an AgentAlertJob property" {
            $global:dbatoolsciOutput[0].PSObject.Properties["AgentAlertJob"] | Should -Not -BeNullOrEmpty
        }

        It "Should have an AgentNotify property" {
            $global:dbatoolsciOutput[0].PSObject.Properties["AgentNotify"] | Should -Not -BeNullOrEmpty
        }

        It "Should have a TargetServerVersion property" {
            $global:dbatoolsciOutput[0].PSObject.Properties["TargetServerVersion"] | Should -Not -BeNullOrEmpty
        }

        It "Should return a mutable object -- properties can be set" {
            $options = New-DbaScriptingOption
            $options.ScriptDrops = $true
            $options.WithDependencies = $true
            $options.Indexes = $true
            $options.ScriptDrops | Should -Be $true
            $options.WithDependencies | Should -Be $true
            $options.Indexes | Should -Be $true
        }

        It "Should return independent objects on each call" {
            $optionsA = New-DbaScriptingOption
            $optionsB = New-DbaScriptingOption
            $optionsA.ScriptDrops = $true
            $optionsB.ScriptDrops | Should -Be $false
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.ScriptingOptions"
        }
    }
}
