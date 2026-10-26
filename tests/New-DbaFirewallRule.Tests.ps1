#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "New-DbaFirewallRule",
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
                "RuleType",
                "Configuration",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag UnitTests {
    InModuleScope dbatools {
        Context "Program path extraction" {
            BeforeEach {
                Mock Invoke-Command2 {
                    [PSCustomObject]@{
                        Successful  = $true
                        CimInstance = [PSCustomObject]@{
                            Status = "The rule was parsed successfully from the store"
                        }
                        Warning     = $null
                        Error       = $null
                        Exception   = $null
                    }
                }
            }

            It "falls back to a port rule when the engine BinaryPath contains sqlservr.exe in a folder name" {
                Mock Get-DbaNetworkConfiguration {
                    [PSCustomObject]@{
                        TcpPort         = "1433"
                        TcpDynamicPorts = ""
                    }
                }
                Mock Get-DbaService {
                    [PSCustomObject]@{
                        BinaryPath = "{0}C:\Backups\sqlservr.exe\bin\realapp.exe{0} -sTEST" -f '"'
                    }
                }

                $result = New-DbaFirewallRule -SqlInstance "sql01\test" -Type Engine -RuleType Program -Confirm:$false -WarningAction SilentlyContinue

                $result.Type | Should -Be "Engine"
                $result.Program | Should -BeNullOrEmpty
                $result.LocalPort | Should -Be "1433"
            }

            It "falls back to the Browser port rule when BinaryPath contains sqlbrowser.exe in a folder name" {
                Mock Get-DbaService {
                    [PSCustomObject]@{
                        BinaryPath = "{0}C:\Backups\sqlbrowser.exe\bin\realapp.exe{0}" -f '"'
                    }
                }

                $result = New-DbaFirewallRule -SqlInstance "sql01\test" -Type Browser -RuleType Program -Confirm:$false -WarningAction SilentlyContinue

                $result.Type | Should -Be "Browser"
                $result.Program | Should -BeNullOrEmpty
                $result.Protocol | Should -Be "UDP"
                $result.LocalPort | Should -Be "1434"
            }
        }

        Context "DAC rule when the path to ERRORLOG cannot be determined" {
            BeforeAll {
                Mock Invoke-Command2 { }
                Mock Get-DbaStartupParameter { }

                $dacErrorMessage = $null
                try {
                    New-DbaFirewallRule -SqlInstance "sql01\test" -Type DAC -EnableException -Confirm:$false
                } catch {
                    $dacErrorMessage = $PSItem.Exception.Message
                }
            }

            It "Reports the missing ERRORLOG instead of failing on a null path" {
                $dacErrorMessage | Should -BeLike "*Failed to get the path to ERRORLOG*"
            }

            It "Does not try to read the ERRORLOG" {
                Should -Invoke Invoke-Command2 -Times 0 -Exactly -Scope Context
            }
        }

        Context "DAC rule when the path to ERRORLOG is found" {
            BeforeAll {
                $dacPassword = ConvertTo-SecureString -String "dbatoolsci_password" -AsPlainText -Force
                $dacCredential = New-Object System.Management.Automation.PSCredential ("dbatoolsci_user", $dacPassword)

                Mock Get-DbaStartupParameter {
                    [PSCustomObject]@{
                        ErrorLog = "C:\SQLLog\ERRORLOG"
                    }
                }
                Mock Invoke-Command2 -ParameterFilter { $Raw } -MockWith {
                    "Dedicated admin connection support was established for listening remotely on port 1434."
                }
                Mock Invoke-Command2 -MockWith {
                    [PSCustomObject]@{
                        Successful  = $true
                        CimInstance = [PSCustomObject]@{
                            Status = "The rule was parsed successfully from the store"
                        }
                        Warning     = $null
                        Error       = $null
                        Exception   = $null
                    }
                }

                $dacResult = New-DbaFirewallRule -SqlInstance "sql01\test" -Type DAC -Credential $dacCredential -Confirm:$false
            }

            It "Creates the firewall rule for the DAC port found in ERRORLOG" {
                $dacResult.Type | Should -Be "DAC"
                $dacResult.LocalPort | Should -Be "1434"
            }

            It "Uses the credential to read the ERRORLOG" {
                Should -Invoke Invoke-Command2 -Times 1 -Exactly -Scope Context -ParameterFilter { $Raw -and $Credential.UserName -eq "dbatoolsci_user" }
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # The context "RuleType Port (traditional port-based rules)" does not work with dynamic ports.
    # So we test at discovery time if dynamic ports are used and skip the tests if so.
    # The Browser tests carry a -Skip as well: the command only creates a Browser rule for a named
    # instance or a static port other than 1433, so a default instance on the default port gets no
    # Browser rule and the negative test runs instead. Computed here because -Skip needs the values
    # at discovery time.
    $singleTcpIpAddresses = Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle -OutputType TcpIpAddresses
    $isUsingDynamicPort = $singleTcpIpAddresses.TcpDynamicPorts -ne ""
    $browserExpected = ([DbaInstanceParameter]$TestConfig.InstanceSingle).InstanceName -ne "MSSQLSERVER" -or ($singleTcpIpAddresses.TcpPort -ne "" -and $singleTcpIpAddresses.TcpPort -ne "1433")

    Context "RuleType Program (default - executable-based rules)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle

            # Create firewall rules with default RuleType (Program)
            # The rule for the DAC can only be created when the instance wrote the DAC port to the
            # current ERRORLOG, which it only does when it starts. On an instance whose ERRORLOG was
            # cycled since then the command warns instead, so the warning is silenced here. It says
            # nothing about the command and a test run must not print warnings.
            $resultsNew = New-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue
            $resultsGet = Get-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle
            $resultsRemoveBrowser = $resultsGet | Where-Object Type -eq "Browser" | Remove-DbaFirewallRule
            $resultsRemove = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -Type AllInstance

            $instanceName = ([DbaInstanceParameter]$TestConfig.InstanceSingle).InstanceName
            # The command names the Engine rule of a default instance differently and only creates
            # a Browser rule when one is needed, so the expectations depend on the instance.
            if ($instanceName -eq "MSSQLSERVER") {
                $expectedEngineRuleName = "SQL Server default instance"
            } else {
                $expectedEngineRuleName = "SQL Server instance $instanceName"
            }
            if ($browserExpected) {
                $expectedMinimumRuleCount = 2
            } else {
                $expectedMinimumRuleCount = 1
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "creates at least the expected number of firewall rules" {
            @($resultsNew).Count | Should -BeGreaterOrEqual $expectedMinimumRuleCount
        }

        It "creates first firewall rule for SQL Server instance" {
            $resultsNew[0].Successful | Should -Be $true
            $resultsNew[0].Type | Should -Be "Engine"
            $resultsNew[0].DisplayName | Should -Be $expectedEngineRuleName
            $resultsNew[0].Status | Should -Be "The rule was successfully created."
        }

        It "creates second firewall rule for SQL Server Browser" -Skip:(-not $browserExpected) {
            $resultsNew[1].Successful | Should -Be $true
            $resultsNew[1].Type | Should -Be "Browser"
            $resultsNew[1].DisplayName | Should -Be "SQL Server Browser"
            $resultsNew[1].Status | Should -Be "The rule was successfully created."
        }

        It "creates no firewall rule for SQL Server Browser" -Skip:$browserExpected {
            # A default instance on the default port is reachable without the Browser, so the
            # command must not create a rule for it.
            $resultsNew.Type | Should -Not -Contain "Browser"
        }

        It "returns at least the expected number of firewall rules" {
            @($resultsGet).Count | Should -BeGreaterOrEqual $expectedMinimumRuleCount
        }

        It "returns firewall rule for SQL Server instance with Program" {
            $resultInstance = $resultsGet | Where-Object Type -eq "Engine"
            $resultInstance.Protocol | Should -Be "TCP"
            $resultInstance.Program | Should -BeLike "*sqlservr.exe"
        }

        It "returns firewall rule for SQL Server Browser with Program" -Skip:(-not $browserExpected) {
            $resultBrowser = $resultsGet | Where-Object Type -eq "Browser"
            # Browser in Program mode should have Protocol = Any and Program path
            if ($resultBrowser.Program) {
                $resultBrowser.Program | Should -BeLike "*sqlbrowser.exe"
                $resultBrowser.Protocol | Should -Be "Any"
            } else {
                # Fallback to port-based if Program couldn't be determined
                $resultBrowser.Protocol | Should -Be "UDP"
                $resultBrowser.LocalPort | Should -Be "1434"
            }
        }

        It "removes firewall rule for Browser" -Skip:(-not $browserExpected) {
            $resultsRemoveBrowser.Type | Should -Be "Browser"
            $resultsRemoveBrowser.IsRemoved | Should -Be $true
            $resultsRemoveBrowser.Status | Should -Be "The rule was successfully removed."
        }

        It "removes other firewall rules" {
            $resultsRemove.Type | Should -Contain "Engine"
            $resultsRemove.IsRemoved | Should -Contain $true
            $resultsRemove.Status | Should -Contain "The rule was successfully removed."
        }
    }

    Context "RuleType Port (traditional port-based rules)" -Skip:$isUsingDynamicPort {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle

            # Create firewall rules with RuleType Port
            # Same as above: without the DAC port in the current ERRORLOG the command warns.
            $resultsNewPort = New-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -RuleType Port -WarningAction SilentlyContinue
            $resultsGetPort = Get-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle
            $resultsRemovePort = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -Type AllInstance

            $instanceName = ([DbaInstanceParameter]$TestConfig.InstanceSingle).InstanceName
            # Same as above: the expectations depend on the instance.
            if ($instanceName -eq "MSSQLSERVER") {
                $expectedEngineRuleName = "SQL Server default instance"
            } else {
                $expectedEngineRuleName = "SQL Server instance $instanceName"
            }
            if ($browserExpected) {
                $expectedMinimumRuleCount = 2
            } else {
                $expectedMinimumRuleCount = 1
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "creates at least the expected number of firewall rules" {
            @($resultsNewPort).Count | Should -BeGreaterOrEqual $expectedMinimumRuleCount
        }

        It "creates first firewall rule for SQL Server instance" {
            $resultsNewPort[0].Successful | Should -Be $true
            $resultsNewPort[0].Type | Should -Be "Engine"
            $resultsNewPort[0].DisplayName | Should -Be $expectedEngineRuleName
            $resultsNewPort[0].Status | Should -Be "The rule was successfully created."
        }

        It "creates second firewall rule for SQL Server Browser" -Skip:(-not $browserExpected) {
            $resultsNewPort[1].Successful | Should -Be $true
            $resultsNewPort[1].Type | Should -Be "Browser"
            $resultsNewPort[1].DisplayName | Should -Be "SQL Server Browser"
            $resultsNewPort[1].Status | Should -Be "The rule was successfully created."
        }

        It "creates no firewall rule for SQL Server Browser" -Skip:$browserExpected {
            # A default instance on the default port is reachable without the Browser, so the
            # command must not create a rule for it.
            $resultsNewPort.Type | Should -Not -Contain "Browser"
        }

        It "returns firewall rule for SQL Server instance with LocalPort" {
            $resultInstance = $resultsGetPort | Where-Object Type -eq "Engine"
            $resultInstance.Protocol | Should -Be "TCP"
            $resultInstance.LocalPort | Should -Not -BeNullOrEmpty
        }

        It "returns firewall rule for SQL Server Browser with port 1434" -Skip:(-not $browserExpected) {
            $resultBrowser = $resultsGetPort | Where-Object Type -eq "Browser"
            $resultBrowser.Protocol | Should -Be "UDP"
            $resultBrowser.LocalPort | Should -Be "1434"
        }

        It "removes firewall rules" {
            $resultsRemovePort.Type | Should -Contain "Engine"
            $resultsRemovePort.IsRemoved | Should -Contain $true
            $resultsRemovePort.Status | Should -Contain "The rule was successfully removed."
        }
    }
}