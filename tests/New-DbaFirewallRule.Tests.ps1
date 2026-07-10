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
    }
}

Describe $CommandName -Tag IntegrationTests {
    # The context "RuleType Port (traditional port-based rules)" does not work with dynamic ports.
    # So we test at discovery time if dynamic ports are used and skip the tests if so.
    $isUsingDynamicPort = (Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle -OutputType TcpIpAddresses).TcpDynamicPorts -ne ''

    # A default instance on the standard port yields ONLY the Engine rule (no Browser, and no remote DAC
    # on this lab), so the Browser/second-rule assertions are skipped when InstanceSingle is a default
    # instance. Named instances (e.g. on AppVeyor) still run the full set.
    $isDefaultInstance = ([DbaInstanceParameter]$TestConfig.InstanceSingle).InstanceName -eq "MSSQLSERVER"

    Context "RuleType Program (default - executable-based rules)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle

            # Create firewall rules with default RuleType (Program)
            $resultsNew = New-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle
            $resultsGet = Get-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle
            $resultsRemoveBrowser = $resultsGet | Where-Object Type -eq "Browser" | Remove-DbaFirewallRule
            $resultsRemove = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -Type AllInstance

            $instanceName = ([DbaInstanceParameter]$TestConfig.InstanceSingle).InstanceName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "creates at least two firewall rules" -Skip:$isDefaultInstance {
            $resultsNew.Count | Should -BeGreaterOrEqual 2
        }

        It "creates first firewall rule for SQL Server instance" {
            $expectedDisplayName = if ($instanceName -eq "MSSQLSERVER") { "SQL Server default instance" } else { "SQL Server instance $instanceName" }
            $resultsNew[0].Successful | Should -Be $true
            $resultsNew[0].Type | Should -Be "Engine"
            $resultsNew[0].DisplayName | Should -Be $expectedDisplayName
            $resultsNew[0].Status | Should -Be "The rule was successfully created."
        }

        It "creates second firewall rule for SQL Server Browser" -Skip:$isDefaultInstance {
            $resultsNew[1].Successful | Should -Be $true
            $resultsNew[1].Type | Should -Be "Browser"
            $resultsNew[1].DisplayName | Should -Be "SQL Server Browser"
            $resultsNew[1].Status | Should -Be "The rule was successfully created."
        }

        It "returns at least two firewall rules" -Skip:$isDefaultInstance {
            $resultsGet.Count | Should -BeGreaterOrEqual 2
        }

        It "returns firewall rule for SQL Server instance with Program" {
            $resultInstance = $resultsGet | Where-Object Type -eq "Engine"
            $resultInstance.Protocol | Should -Be "TCP"
            $resultInstance.Program | Should -BeLike "*sqlservr.exe"
        }

        It "returns firewall rule for SQL Server Browser with Program" -Skip:$isDefaultInstance {
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

        It "removes firewall rule for Browser" -Skip:$isDefaultInstance {
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
            $resultsNewPort = New-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -RuleType Port
            $resultsGetPort = Get-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle
            $resultsRemovePort = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -Type AllInstance

            $instanceName = ([DbaInstanceParameter]$TestConfig.InstanceSingle).InstanceName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "creates at least two firewall rules" -Skip:$isDefaultInstance {
            $resultsNewPort.Count | Should -BeGreaterOrEqual 2
        }

        It "creates first firewall rule for SQL Server instance" {
            $expectedDisplayName = if ($instanceName -eq "MSSQLSERVER") { "SQL Server default instance" } else { "SQL Server instance $instanceName" }
            $resultsNewPort[0].Successful | Should -Be $true
            $resultsNewPort[0].Type | Should -Be "Engine"
            $resultsNewPort[0].DisplayName | Should -Be $expectedDisplayName
            $resultsNewPort[0].Status | Should -Be "The rule was successfully created."
        }

        It "creates second firewall rule for SQL Server Browser" -Skip:$isDefaultInstance {
            $resultsNewPort[1].Successful | Should -Be $true
            $resultsNewPort[1].Type | Should -Be "Browser"
            $resultsNewPort[1].DisplayName | Should -Be "SQL Server Browser"
            $resultsNewPort[1].Status | Should -Be "The rule was successfully created."
        }

        It "returns firewall rule for SQL Server instance with LocalPort" {
            $resultInstance = $resultsGetPort | Where-Object Type -eq "Engine"
            $resultInstance.Protocol | Should -Be "TCP"
            $resultInstance.LocalPort | Should -Not -BeNullOrEmpty
        }

        It "returns firewall rule for SQL Server Browser with port 1434" -Skip:$isDefaultInstance {
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

Describe $CommandName -Tag UnitTests {
    InModuleScope dbatools {
        # These exercise the CMDLET'S OWN config bag and its status-append path (not a framework comparer).
        # SqlInstance is LOCALHOST so RemoteExecutionService takes its in-process path (a local Invoke-Command
        # with no -Session, in the current runspace) where the New-NetFirewallRule mock IS visible - so no
        # real firewall rule is ever created; each test asserts the mock was actually invoked to prove it. A
        # Port rule takes the Get-DbaNetworkConfiguration port and never parses a service BinaryPath.
        Context "Config bag and status-append reflect PS semantics" {
            BeforeEach {
                Mock Get-DbaNetworkConfiguration {
                    [PSCustomObject]@{
                        TcpPort         = "1433"
                        TcpDynamicPorts = ""
                    }
                }
            }

            It "merges -Configuration into the config bag using the CURRENT culture per call (en-US then tr-TR)" {
                Mock New-NetFirewallRule {
                    [PSCustomObject]@{ Status = "The rule was parsed successfully from the store" }
                }
                # The comparer must be read PER CALL, not captured once. Warm up under en-US (a regressed static
                # comparer would snapshot en-US here), THEN switch to tr-TR and merge "DIRECTION" over the
                # default "Direction" key. Under tr-TR the dotless-I means DIRECTION != Direction, so a per-call
                # CurrentCultureIgnoreCase (net472 @{}) keeps BOTH keys, while OrdinalIgnoreCase (net8.0 @{})
                # still collapses them. A static en-US comparer would collapse on BOTH editions and fail net472.
                $originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
                try {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = New-Object System.Globalization.CultureInfo "en-US"
                    $splatWarmup = @{
                        SqlInstance   = "localhost"
                        Type          = "Engine"
                        RuleType      = "Port"
                        Configuration = @{ DIRECTION = "Outbound" }
                        Confirm       = $false
                        WarningAction = "SilentlyContinue"
                    }
                    $null = New-DbaFirewallRule @splatWarmup

                    [System.Threading.Thread]::CurrentThread.CurrentCulture = New-Object System.Globalization.CultureInfo "tr-TR"
                    $splatFirewallRule = @{
                        SqlInstance   = "localhost"
                        Type          = "Engine"
                        RuleType      = "Port"
                        Configuration = @{ DIRECTION = "Outbound" }
                        Confirm       = $false
                        WarningAction = "SilentlyContinue"
                    }
                    $result = New-DbaFirewallRule @splatFirewallRule
                } finally {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
                }

                Should -Invoke New-NetFirewallRule -Scope It
                $directionKeys = @($result.RuleConfig.Keys | Where-Object { "$PSItem" -match "^direction$" })
                if ($PSVersionTable.PSEdition -eq "Core") {
                    $directionKeys.Count | Should -Be 1
                    $result.RuleConfig["Direction"] | Should -Be "Outbound"
                } else {
                    $directionKeys.Count | Should -Be 2
                    $result.RuleConfig["Direction"] | Should -Be "Inbound"
                }
            }

            It "joins a multi-element Warning with the default `$OFS (single space), not the collection type name" {
                Mock New-NetFirewallRule {
                    Write-Warning "first warning"
                    Write-Warning "second warning"
                    [PSCustomObject]@{ Status = "The rule was parsed successfully from the store" }
                }
                $splatFirewallRule = @{
                    SqlInstance   = "localhost"
                    Type          = "Engine"
                    RuleType      = "Port"
                    Confirm       = $false
                    WarningAction = "SilentlyContinue"
                }
                $result = New-DbaFirewallRule @splatFirewallRule
                Should -Invoke New-NetFirewallRule -Scope It
                $result.Status | Should -Match "Warning: first warning second warning\."
                $result.Status | Should -Not -Match "System.Collections"
            }

            It "joins a multi-element Error with the default `$OFS (single space)" {
                Mock New-NetFirewallRule {
                    Write-Error "first error"
                    Write-Error "second error"
                    [PSCustomObject]@{ Status = "The rule was parsed successfully from the store" }
                }
                $splatFirewallRule = @{
                    SqlInstance   = "localhost"
                    Type          = "Engine"
                    RuleType      = "Port"
                    Confirm       = $false
                    WarningAction = "SilentlyContinue"
                }
                $result = New-DbaFirewallRule @splatFirewallRule
                Should -Invoke New-NetFirewallRule -Scope It
                $result.Status | Should -Match "Error: first error second error\."
                $result.Status | Should -Not -Match "System.Collections"
            }

            It "honors a session `$OFS override when joining the Warning collection" {
                Mock New-NetFirewallRule {
                    Write-Warning "first warning"
                    Write-Warning "second warning"
                    [PSCustomObject]@{ Status = "The rule was parsed successfully from the store" }
                }
                $splatFirewallRule = @{
                    SqlInstance   = "localhost"
                    Type          = "Engine"
                    RuleType      = "Port"
                    Confirm       = $false
                    WarningAction = "SilentlyContinue"
                }
                # Capture $OFS's ORIGINAL state (it is usually undefined) and restore it EXACTLY afterward -
                # setting it to " " would leak a defined module-scope $OFS across tests.
                $ofsExisted = Test-Path Variable:OFS
                $ofsOriginal = if ($ofsExisted) { Get-Variable -Name OFS -ValueOnly } else { $null }
                $OFS = ","
                try {
                    $result = New-DbaFirewallRule @splatFirewallRule
                    $result.Status | Should -Match "Warning: first warning,second warning\."
                } finally {
                    if ($ofsExisted) {
                        Set-Variable -Name OFS -Value $ofsOriginal
                    } else {
                        Remove-Variable -Name OFS -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }
}