#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Set-DbaFirewallRule",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Credential",
                "Type",
                "InputObject",
                "Configuration",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag UnitTests {
    InModuleScope dbatools {
        # A rule whose ComputerName is LOCALHOST so RemoteExecutionService takes its in-process path
        # (a local Invoke-Command with no -Session, in the current runspace) where the
        # Set-NetFirewallRule mock IS visible - so no real firewall rule is ever edited; each test
        # asserts the mock was actually invoked to prove it. The rule is fed on the pipeline exactly
        # as Get-DbaFirewallRule would emit it (ComputerName/Name/Credential stamped on).
        Context "Config bag and status-append reflect PS semantics" {
            BeforeEach {
                $script:rule = [PSCustomObject]@{
                    ComputerName = "localhost"
                    InstanceName = "MSSQLSERVER"
                    SqlInstance  = "localhost"
                    DisplayName  = "SQL Server default instance"
                    Name         = "SQL Server default instance"
                    Type         = "Engine"
                    Protocol     = "TCP"
                    LocalPort    = "1433"
                    Program      = "C:\sqlservr.exe"
                    Rule         = $null
                    Credential   = $null
                }
            }

            It "copies -Configuration, strips the reserved keys and does not mutate the caller's hashtable" {
                Mock Set-NetFirewallRule { }

                $splatConfig = @{
                    Name        = "reserved-name"
                    DisplayName = "reserved-display"
                    Group       = "reserved-group"
                    Enabled     = "False"
                }
                $result = $script:rule | Set-DbaFirewallRule -Configuration $splatConfig -Confirm:$false -WarningAction SilentlyContinue

                Should -Invoke Set-NetFirewallRule -Scope It
                $result.RuleConfig.Keys | Should -Not -Contain "Name"
                $result.RuleConfig.Keys | Should -Not -Contain "DisplayName"
                $result.RuleConfig.Keys | Should -Not -Contain "Group"
                $result.RuleConfig["Enabled"] | Should -Be "False"
                # The caller still owns all three reserved keys - Set- copies before stripping.
                $splatConfig.ContainsKey("Name") | Should -BeTrue
                $splatConfig.ContainsKey("DisplayName") | Should -BeTrue
                $splatConfig.ContainsKey("Group") | Should -BeTrue
                $result.Successful | Should -BeTrue
                $result.Status | Should -Be "The rule was successfully set."
            }

            It "does not invoke Set-NetFirewallRule under -WhatIf" {
                Mock Set-NetFirewallRule { }

                $null = $script:rule | Set-DbaFirewallRule -Configuration @{ Enabled = "False" } -WhatIf
                Should -Invoke Set-NetFirewallRule -Times 0 -Scope It
            }

            It "joins a multi-element Warning with the default `$OFS (single space), not the collection type name" {
                Mock Set-NetFirewallRule {
                    Write-Warning "first warning"
                    Write-Warning "second warning"
                }
                $result = $script:rule | Set-DbaFirewallRule -Configuration @{ Enabled = "True" } -Confirm:$false -WarningAction SilentlyContinue

                Should -Invoke Set-NetFirewallRule -Scope It
                $result.Successful | Should -BeFalse
                $result.Status | Should -Match "Warning: first warning second warning\."
                $result.Status | Should -Not -Match "System.Collections"
            }

            It "joins a multi-element Error with the default `$OFS (single space)" {
                Mock Set-NetFirewallRule {
                    Write-Error "first error"
                    Write-Error "second error"
                }
                $result = $script:rule | Set-DbaFirewallRule -Configuration @{ Enabled = "True" } -Confirm:$false -WarningAction SilentlyContinue

                Should -Invoke Set-NetFirewallRule -Scope It
                $result.Successful | Should -BeFalse
                $result.Status | Should -Match "Error: first error second error\."
                $result.Status | Should -Not -Match "System.Collections"
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # The rule is applied to a remote computer, so the whole Describe is skipped on AppVeyor per
    # specs/appveyor-ci-capabilities.md; the lab gate runs it against InstanceSingle.
    Context "Editing existing SQL Server firewall rules" -Skip:$env:appveyor {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -Type AllInstance -WarningAction SilentlyContinue
            $null = New-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -Type Engine
            $null = New-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -Type Browser

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -Type AllInstance -WarningAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "edits an existing rule in place and reports success" {
            $splatSet = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Type            = "Engine"
                Configuration   = @{ Description = "dbatools set test one" }
                Confirm         = $false
                EnableException = $true
            }
            $result = Set-DbaFirewallRule @splatSet
            $result.Type | Should -Be "Engine"
            $result.Successful | Should -Be $true
            $result.Status | Should -Be "The rule was successfully set."

            # Read the change back from the target computer to prove the edit landed.
            $engine = Get-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -Type Engine -EnableException
            $engine.Rule.Description | Should -Be "dbatools set test one"
        }

        It "does not change the rule under -WhatIf" {
            $splatBefore = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Type            = "Engine"
                Configuration   = @{ Description = "before whatif" }
                Confirm         = $false
                EnableException = $true
            }
            $null = Set-DbaFirewallRule @splatBefore

            $splatWhatIf = @{
                SqlInstance   = $TestConfig.InstanceSingle
                Type          = "Engine"
                Configuration = @{ Description = "after whatif" }
                WhatIf        = $true
            }
            $null = Set-DbaFirewallRule @splatWhatIf

            $engine = Get-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -Type Engine -EnableException
            $engine.Rule.Description | Should -Be "before whatif"
        }

        It "edits every piped rule (N-in/N-out) and honors the credential on each object" {
            $rules = Get-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -Type AllInstance -EnableException
            $ruleCount = @($rules).Count
            $ruleCount | Should -BeGreaterOrEqual 2

            $results = $rules | Set-DbaFirewallRule -Configuration @{ Description = "bulk set test" } -Confirm:$false -EnableException
            @($results).Count | Should -Be $ruleCount
            $results.Successful | Should -Not -Contain $false

            $after = Get-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -Type AllInstance -EnableException
            foreach ($rule in $after) {
                $rule.Rule.Description | Should -Be "bulk set test"
            }
        }

        It "reports failure without terminating when the rule does not exist" {
            $computerName = ([DbaInstanceParameter]$TestConfig.InstanceSingle).ComputerName
            $missingRule = [PSCustomObject]@{
                ComputerName = $computerName
                InstanceName = "MSSQLSERVER"
                SqlInstance  = $computerName
                DisplayName  = "does not exist"
                Name         = "dbatools nonexistent firewall rule"
                Type         = "Engine"
                Protocol     = "TCP"
                LocalPort    = "1433"
                Program      = $null
                Rule         = $null
                Credential   = $null
            }
            $result = $missingRule | Set-DbaFirewallRule -Configuration @{ Description = "x" } -Confirm:$false -WarningAction SilentlyContinue
            $result.Successful | Should -Be $false
            $result.Status | Should -Match "Failure"
        }
    }
}
