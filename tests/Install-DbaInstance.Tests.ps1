#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Install-DbaInstance",
    $PSDefaultParameterValues = $TestConfig.Defaults
)
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    BeforeAll {
        # Prevent the functions from executing dangerous stuff and getting right responses where needed
        Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]0 } } -ModuleName dbatools
        Mock -CommandName Test-PendingReboot -MockWith { $false } -ModuleName dbatools
        Mock -CommandName Test-ElevationRequirement -MockWith { $null } -ModuleName dbatools
        Mock -CommandName Restart-Computer -MockWith { $null } -ModuleName dbatools
        Mock -CommandName Register-RemoteSessionConfiguration -ModuleName dbatools -MockWith {
            [PSCustomObject]@{ "Name" = "dbatoolsInstallSqlServerUpdate" ; Successful = $true ; Status = "Dummy" }
        }
        Mock -CommandName Unregister-RemoteSessionConfiguration -ModuleName dbatools -MockWith {
            [PSCustomObject]@{ "Name" = "dbatoolsInstallSqlServerUpdate" ; Successful = $true ; Status = "Dummy" }
        }
        Mock -CommandName Set-DbaPrivilege -ModuleName dbatools -MockWith { }
        Mock -CommandName Set-DbaTcpPort -ModuleName dbatools -MockWith { }
        Mock -CommandName Restart-DbaService -ModuleName dbatools -MockWith { }
        Mock -CommandName Get-DbaCmObject -ModuleName dbatools -MockWith { [PSCustomObject]@{NumberOfCores = 24 } } -ParameterFilter { $ClassName -eq "Win32_processor" }
        # mock searching for setup, proper file should always it find
        Mock -CommandName Find-SqlInstanceSetup -MockWith {
            Get-ChildItem $Path -Filter "dummy.exe" -ErrorAction Stop | Select-Object -ExpandProperty FullName -First 1
        } -ModuleName dbatools
        $null = New-Item -ItemType File -Path TestDrive:\dummy.exe -Force
        $null = New-Item -ItemType File -Path TestDrive:\dummy.exe -Force
    }

    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Version",
                "InstanceName",
                "SaCredential",
                "Credential",
                "Authentication",
                "ConfigurationFile",
                "Configuration",
                "Path",
                "Feature",
                "AuthenticationMode",
                "InstancePath",
                "DataPath",
                "LogPath",
                "TempPath",
                "BackupPath",
                "UpdateSourcePath",
                "AdminAccount",
                "Port",
                "Throttle",
                "ProductID",
                "AsCollation",
                "SqlCollation",
                "EngineCredential",
                "AgentCredential",
                "ASCredential",
                "ISCredential",
                "RSCredential",
                "FTCredential",
                "PBEngineCredential",
                "SaveConfiguration",
                "PerformVolumeMaintenanceTasks",
                "Restart",
                "NoPendingRenameCheck",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Validate installs of each version" {
        BeforeAll {
            $cred = New-Object PSCredential("foo", (ConvertTo-SecureString "bar" -Force -AsPlainText))
        }

        Context "SQL Server 2008" {
            BeforeAll {
                $version = "2008"
                [version]$canonicVersion = "10.0"
                $mainNode = "SQLSERVER2008"
                # Create a dummy Configuration.ini
                @(
                    "[$mainNode]"
                    'SQLSVCACCOUNT="foo\bar"'
                    'FEATURES="SQLEngine,AS"'
                    'ACTION="Install"'
                ) | Set-Content -Path TestDrive:\Configuration.ini -Force
            }

            It "Should install SQL$version with all features enabled" {
                $result = Install-DbaInstance -Version $version -Path TestDrive: -EnableException -Confirm:$false -Feature All
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.Version | Should -Be $canonicVersion
                $result.Port | Should -Be $null
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
            }

            It "Should install SQL$version with custom parameters" {
                $params = @{
                    SAPWD = "foo"
                }
                $splatInstall = @{
                    SqlInstance                   = "localhost\NewInstance:13337"
                    Version                       = $version
                    Path                          = "TestDrive:"
                    Configuration                 = $params
                    EngineCredential              = $cred
                    SaCredential                  = $cred
                    Port                          = 1337
                    PerformVolumeMaintenanceTasks = $true
                    AdminAccount                  = "local\foo", "local\bar"
                }
                $result = Install-DbaInstance @splatInstall -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Set-DbaPrivilege -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Set-DbaTcpPort -Exactly 1 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.InstanceName | Should -Be NewInstance
                $result.Version | Should -Be $canonicVersion
                $result.SACredential.GetNetworkCredential().Password | Should -Be $cred.GetNetworkCredential().Password
                $result.Port | Should -Be 1337
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).SAPWD | Should -Be "foo"
                $result.Configuration.$($mainNode).SQLSVCACCOUNT | Should -Be "foo"
                $result.Configuration.$($mainNode).SQLSYSADMINACCOUNTS | Should -Be '"local\foo" "local\bar"'
            }

            It "Should install SQL$version with custom configuration file" {
                $splatConfig = @{
                    SqlInstance       = "localhost\NewInstance:13337"
                    Version           = $version
                    Path              = "TestDrive:"
                    ConfigurationFile = "TestDrive:\Configuration.ini"
                }
                $result = Install-DbaInstance @splatConfig -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.InstanceName | Should -Be NewInstance
                $result.Version | Should -Be $canonicVersion
                $result.Port | Should -Be 13337
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).FEATURES | Should -Be "SQLEngine,AS"
                $result.Configuration.$($mainNode).SQLSVCACCOUNT | Should -Be "foo\bar"
            }

            It "Should install SQL$version slipstreaming the updates" {
                $result = Install-DbaInstance -Version $version -Path TestDrive: -EnableException -Confirm:$false -UpdateSourcePath TestDrive:
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.InstanceName | Should -Be MSSQLSERVER
                $result.Version | Should -Be $canonicVersion
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).UPDATESOURCE | Should -Be "TestDrive:"
                $result.Configuration.$($mainNode).UPDATEENABLED | Should -Be "True"
            }

            It "Should install SQL$version with default features and restart" {
                # temporary replacing that mock with exit code 3010
                Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]3010 } } -ModuleName dbatools
                $splatRestart = @{
                    Version = $version
                    Path    = "TestDrive:"
                    Restart = $true
                }
                $result = Install-DbaInstance @splatRestart -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Restart-Computer -Exactly 1 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.Version | Should -Be $canonicVersion
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $true
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).FEATURES -join "," | Should -BeLike *SQLEngine*

                # reverting the mock
                Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]0 } } -ModuleName dbatools
            }

            It "Should install tools for SQL$version" {
                Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]0 } } -ModuleName dbatools
                $splatTools = @{
                    Version = $version
                    Path    = "TestDrive:"
                    Feature = "Tools"
                }
                $result = Install-DbaInstance @splatTools -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.Version | Should -Be $canonicVersion
                $result.Successful | Should -Be $true
                "BC" | Should -BeIn $result.Configuration.$($mainNode).FEATURES
                "Conn" | Should -BeIn $result.Configuration.$($mainNode).FEATURES
                "SSMS" | Should -BeIn $result.Configuration.$($mainNode).FEATURES
                "ADV_SSMS" | Should -BeIn $result.Configuration.$($mainNode).FEATURES
            }
        }

        Context "SQL Server 2008R2" {
            BeforeAll {
                $version = "2008R2"
                [version]$canonicVersion = "10.50"
                $mainNode = "SQLSERVER2008"
                # Create a dummy Configuration.ini
                @(
                    "[$mainNode]"
                    'SQLSVCACCOUNT="foo\bar"'
                    'FEATURES="SQLEngine,AS"'
                    'ACTION="Install"'
                ) | Set-Content -Path TestDrive:\Configuration.ini -Force
            }

            It "Should install SQL$version with all features enabled" {
                $result = Install-DbaInstance -Version $version -Path TestDrive: -EnableException -Confirm:$false -Feature All
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.Version | Should -Be $canonicVersion
                $result.Port | Should -Be $null
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
            }

            It "Should install SQL$version with custom parameters" {
                $params = @{
                    SAPWD = "foo"
                }
                $splatInstall = @{
                    SqlInstance                   = "localhost\NewInstance:13337"
                    Version                       = $version
                    Path                          = "TestDrive:"
                    Configuration                 = $params
                    EngineCredential              = $cred
                    SaCredential                  = $cred
                    Port                          = 1337
                    PerformVolumeMaintenanceTasks = $true
                    AdminAccount                  = "local\foo", "local\bar"
                }
                $result = Install-DbaInstance @splatInstall -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Set-DbaPrivilege -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Set-DbaTcpPort -Exactly 1 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.InstanceName | Should -Be NewInstance
                $result.Version | Should -Be $canonicVersion
                $result.SACredential.GetNetworkCredential().Password | Should -Be $cred.GetNetworkCredential().Password
                $result.Port | Should -Be 1337
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).SAPWD | Should -Be "foo"
                $result.Configuration.$($mainNode).SQLSVCACCOUNT | Should -Be "foo"
                $result.Configuration.$($mainNode).SQLSYSADMINACCOUNTS | Should -Be '"local\foo" "local\bar"'
            }

            It "Should install SQL$version with custom configuration file" {
                $splatConfig = @{
                    SqlInstance       = "localhost\NewInstance:13337"
                    Version           = $version
                    Path              = "TestDrive:"
                    ConfigurationFile = "TestDrive:\Configuration.ini"
                }
                $result = Install-DbaInstance @splatConfig -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.InstanceName | Should -Be NewInstance
                $result.Version | Should -Be $canonicVersion
                $result.Port | Should -Be 13337
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).FEATURES | Should -Be "SQLEngine,AS"
                $result.Configuration.$($mainNode).SQLSVCACCOUNT | Should -Be "foo\bar"
            }

            It "Should install SQL$version slipstreaming the updates" {
                $result = Install-DbaInstance -Version $version -Path TestDrive: -EnableException -Confirm:$false -UpdateSourcePath TestDrive:
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.InstanceName | Should -Be MSSQLSERVER
                $result.Version | Should -Be $canonicVersion
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).UPDATESOURCE | Should -Be "TestDrive:"
                $result.Configuration.$($mainNode).UPDATEENABLED | Should -Be "True"
            }

            It "Should install SQL$version with default features and restart" {
                # temporary replacing that mock with exit code 3010
                Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]3010 } } -ModuleName dbatools
                $splatRestart = @{
                    Version = $version
                    Path    = "TestDrive:"
                    Restart = $true
                }
                $result = Install-DbaInstance @splatRestart -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Restart-Computer -Exactly 1 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.Version | Should -Be $canonicVersion
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $true
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).FEATURES -join "," | Should -BeLike *SQLEngine*

                # reverting the mock
                Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]0 } } -ModuleName dbatools
            }

            It "Should install tools for SQL$version" {
                Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]0 } } -ModuleName dbatools
                $splatTools = @{
                    Version = $version
                    Path    = "TestDrive:"
                    Feature = "Tools"
                }
                $result = Install-DbaInstance @splatTools -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.Version | Should -Be $canonicVersion
                $result.Successful | Should -Be $true
                "BC" | Should -BeIn $result.Configuration.$($mainNode).FEATURES
                "Conn" | Should -BeIn $result.Configuration.$($mainNode).FEATURES
                "SSMS" | Should -BeIn $result.Configuration.$($mainNode).FEATURES
                "ADV_SSMS" | Should -BeIn $result.Configuration.$($mainNode).FEATURES
            }
        }

        Context "SQL Server 2012" {
            BeforeAll {
                $version = "2012"
                [version]$canonicVersion = "11.0"
                $mainNode = "OPTIONS"
                # Create a dummy Configuration.ini
                @(
                    "[$mainNode]"
                    'SQLSVCACCOUNT="foo\bar"'
                    'FEATURES="SQLEngine,AS"'
                    'ACTION="Install"'
                ) | Set-Content -Path TestDrive:\Configuration.ini -Force
            }

            It "Should install SQL$version with all features enabled" {
                $result = Install-DbaInstance -Version $version -Path TestDrive: -EnableException -Confirm:$false -Feature All
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.Version | Should -Be $canonicVersion
                $result.Port | Should -Be $null
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
            }

            It "Should install SQL$version with custom parameters" {
                $params = @{
                    SAPWD = "foo"
                }
                $splatInstall = @{
                    SqlInstance                   = "localhost\NewInstance:13337"
                    Version                       = $version
                    Path                          = "TestDrive:"
                    Configuration                 = $params
                    EngineCredential              = $cred
                    SaCredential                  = $cred
                    Port                          = 1337
                    PerformVolumeMaintenanceTasks = $true
                    AdminAccount                  = "local\foo", "local\bar"
                }
                $result = Install-DbaInstance @splatInstall -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Set-DbaPrivilege -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Set-DbaTcpPort -Exactly 1 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.InstanceName | Should -Be NewInstance
                $result.Version | Should -Be $canonicVersion
                $result.SACredential.GetNetworkCredential().Password | Should -Be $cred.GetNetworkCredential().Password
                $result.Port | Should -Be 1337
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).SAPWD | Should -Be "foo"
                $result.Configuration.$($mainNode).SQLSVCACCOUNT | Should -Be "foo"
                $result.Configuration.$($mainNode).SQLSYSADMINACCOUNTS | Should -Be '"local\foo" "local\bar"'
            }

            It "Should install SQL$version with custom configuration file" {
                $splatConfig = @{
                    SqlInstance       = "localhost\NewInstance:13337"
                    Version           = $version
                    Path              = "TestDrive:"
                    ConfigurationFile = "TestDrive:\Configuration.ini"
                }
                $result = Install-DbaInstance @splatConfig -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.InstanceName | Should -Be NewInstance
                $result.Version | Should -Be $canonicVersion
                $result.Port | Should -Be 13337
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).FEATURES | Should -Be "SQLEngine,AS"
                $result.Configuration.$($mainNode).SQLSVCACCOUNT | Should -Be "foo\bar"
            }

            It "Should install SQL$version slipstreaming the updates" {
                $result = Install-DbaInstance -Version $version -Path TestDrive: -EnableException -Confirm:$false -UpdateSourcePath TestDrive:
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.InstanceName | Should -Be MSSQLSERVER
                $result.Version | Should -Be $canonicVersion
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).UPDATESOURCE | Should -Be "TestDrive:"
                $result.Configuration.$($mainNode).UPDATEENABLED | Should -Be "True"
            }

            It "Should install SQL$version with default features and restart" {
                # temporary replacing that mock with exit code 3010
                Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]3010 } } -ModuleName dbatools
                $splatRestart = @{
                    Version = $version
                    Path    = "TestDrive:"
                    Restart = $true
                }
                $result = Install-DbaInstance @splatRestart -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Restart-Computer -Exactly 1 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.Version | Should -Be $canonicVersion
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $true
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).FEATURES -join "," | Should -BeLike *SQLEngine*

                # reverting the mock
                Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]0 } } -ModuleName dbatools
            }

            It "Should install tools for SQL$version" {
                Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]0 } } -ModuleName dbatools
                $splatTools = @{
                    Version = $version
                    Path    = "TestDrive:"
                    Feature = "Tools"
                }
                $result = Install-DbaInstance @splatTools -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.Version | Should -Be $canonicVersion
                $result.Successful | Should -Be $true
                "BC" | Should -BeIn $result.Configuration.$($mainNode).FEATURES
                "Conn" | Should -BeIn $result.Configuration.$($mainNode).FEATURES
                "SSMS" | Should -BeIn $result.Configuration.$($mainNode).FEATURES
                "ADV_SSMS" | Should -BeIn $result.Configuration.$($mainNode).FEATURES
            }
        }

        Context "SQL Server 2014" {
            BeforeAll {
                $version = "2014"
                [version]$canonicVersion = "12.0"
                $mainNode = "OPTIONS"
                # Create a dummy Configuration.ini
                @(
                    "[$mainNode]"
                    'SQLSVCACCOUNT="foo\bar"'
                    'FEATURES="SQLEngine,AS"'
                    'ACTION="Install"'
                ) | Set-Content -Path TestDrive:\Configuration.ini -Force
            }

            It "Should install SQL$version with all features enabled" {
                $result = Install-DbaInstance -Version $version -Path TestDrive: -EnableException -Confirm:$false -Feature All
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.Version | Should -Be $canonicVersion
                $result.Port | Should -Be $null
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
            }

            It "Should install SQL$version with custom parameters" {
                $params = @{
                    SAPWD = "foo"
                }
                $splatInstall = @{
                    SqlInstance                   = "localhost\NewInstance:13337"
                    Version                       = $version
                    Path                          = "TestDrive:"
                    Configuration                 = $params
                    EngineCredential              = $cred
                    SaCredential                  = $cred
                    Port                          = 1337
                    PerformVolumeMaintenanceTasks = $true
                    AdminAccount                  = "local\foo", "local\bar"
                }
                $result = Install-DbaInstance @splatInstall -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Set-DbaPrivilege -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Set-DbaTcpPort -Exactly 1 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.InstanceName | Should -Be NewInstance
                $result.Version | Should -Be $canonicVersion
                $result.SACredential.GetNetworkCredential().Password | Should -Be $cred.GetNetworkCredential().Password
                $result.Port | Should -Be 1337
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).SAPWD | Should -Be "foo"
                $result.Configuration.$($mainNode).SQLSVCACCOUNT | Should -Be "foo"
                $result.Configuration.$($mainNode).SQLSYSADMINACCOUNTS | Should -Be '"local\foo" "local\bar"'
            }

            It "Should install SQL$version with custom configuration file" {
                $splatConfig = @{
                    SqlInstance       = "localhost\NewInstance:13337"
                    Version           = $version
                    Path              = "TestDrive:"
                    ConfigurationFile = "TestDrive:\Configuration.ini"
                }
                $result = Install-DbaInstance @splatConfig -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.InstanceName | Should -Be NewInstance
                $result.Version | Should -Be $canonicVersion
                $result.Port | Should -Be 13337
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).FEATURES | Should -Be "SQLEngine,AS"
                $result.Configuration.$($mainNode).SQLSVCACCOUNT | Should -Be "foo\bar"
            }

            It "Should install SQL$version slipstreaming the updates" {
                $result = Install-DbaInstance -Version $version -Path TestDrive: -EnableException -Confirm:$false -UpdateSourcePath TestDrive:
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.InstanceName | Should -Be MSSQLSERVER
                $result.Version | Should -Be $canonicVersion
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).UPDATESOURCE | Should -Be "TestDrive:"
                $result.Configuration.$($mainNode).UPDATEENABLED | Should -Be "True"
            }

            It "Should install SQL$version with default features and restart" {
                # temporary replacing that mock with exit code 3010
                Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]3010 } } -ModuleName dbatools
                $splatRestart = @{
                    Version = $version
                    Path    = "TestDrive:"
                    Restart = $true
                }
                $result = Install-DbaInstance @splatRestart -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Restart-Computer -Exactly 1 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.Version | Should -Be $canonicVersion
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $true
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).FEATURES -join "," | Should -BeLike *SQLEngine*

                # reverting the mock
                Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]0 } } -ModuleName dbatools
            }

            It "Should install tools for SQL$version" {
                Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]0 } } -ModuleName dbatools
                $splatTools = @{
                    Version = $version
                    Path    = "TestDrive:"
                    Feature = "Tools"
                }
                $result = Install-DbaInstance @splatTools -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.Version | Should -Be $canonicVersion
                $result.Successful | Should -Be $true
                "BC" | Should -BeIn $result.Configuration.$($mainNode).FEATURES
                "Conn" | Should -BeIn $result.Configuration.$($mainNode).FEATURES
                "SSMS" | Should -BeIn $result.Configuration.$($mainNode).FEATURES
                "ADV_SSMS" | Should -BeIn $result.Configuration.$($mainNode).FEATURES
            }
        }

        Context "SQL Server 2016" {
            BeforeAll {
                $version = "2016"
                [version]$canonicVersion = "13.0"
                $mainNode = "OPTIONS"
                # Create a dummy Configuration.ini
                @(
                    "[$mainNode]"
                    'SQLSVCACCOUNT="foo\bar"'
                    'FEATURES="SQLEngine,AS"'
                    'ACTION="Install"'
                ) | Set-Content -Path TestDrive:\Configuration.ini -Force
            }

            It "Should install SQL$version with all features enabled" {
                $result = Install-DbaInstance -Version $version -Path TestDrive: -EnableException -Confirm:$false -Feature All
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.Version | Should -Be $canonicVersion
                $result.Port | Should -Be $null
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).SQLTEMPDBFILECOUNT | Should -Be 8
            }

            It "Should install SQL$version with custom parameters" {
                $params = @{
                    SAPWD = "foo"
                }
                $splatInstall = @{
                    SqlInstance                   = "localhost\NewInstance:13337"
                    Version                       = $version
                    Path                          = "TestDrive:"
                    Configuration                 = $params
                    EngineCredential              = $cred
                    SaCredential                  = $cred
                    Port                          = 1337
                    PerformVolumeMaintenanceTasks = $true
                    AdminAccount                  = "local\foo", "local\bar"
                }
                $result = Install-DbaInstance @splatInstall -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools
                # SQLSVCINSTANTFILEINIT is used for version 2016 and later
                Assert-MockCalled -CommandName Set-DbaPrivilege -Exactly 0 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Set-DbaTcpPort -Exactly 1 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.InstanceName | Should -Be NewInstance
                $result.Version | Should -Be $canonicVersion
                $result.SACredential.GetNetworkCredential().Password | Should -Be $cred.GetNetworkCredential().Password
                $result.Port | Should -Be 1337
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).SAPWD | Should -Be "foo"
                $result.Configuration.$($mainNode).SQLSVCACCOUNT | Should -Be "foo"
                $result.Configuration.$($mainNode).SQLSYSADMINACCOUNTS | Should -Be '"local\foo" "local\bar"'
                $result.Configuration.$($mainNode).SQLTEMPDBFILECOUNT | Should -Be 8
            }

            It "Should install SQL$version with custom configuration file" {
                $splatConfig = @{
                    SqlInstance       = "localhost\NewInstance:13337"
                    Version           = $version
                    Path              = "TestDrive:"
                    ConfigurationFile = "TestDrive:\Configuration.ini"
                }
                $result = Install-DbaInstance @splatConfig -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.InstanceName | Should -Be NewInstance
                $result.Version | Should -Be $canonicVersion
                $result.Port | Should -Be 13337
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).FEATURES | Should -Be "SQLEngine,AS"
                $result.Configuration.$($mainNode).SQLSVCACCOUNT | Should -Be "foo\bar"
                $result.Configuration.$($mainNode).SQLTEMPDBFILECOUNT | Should -Be 8
            }

            It "Should install SQL$version slipstreaming the updates" {
                $result = Install-DbaInstance -Version $version -Path TestDrive: -EnableException -Confirm:$false -UpdateSourcePath TestDrive:
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.InstanceName | Should -Be MSSQLSERVER
                $result.Version | Should -Be $canonicVersion
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).UPDATESOURCE | Should -Be "TestDrive:"
                $result.Configuration.$($mainNode).UPDATEENABLED | Should -Be "True"
            }

            It "Should install SQL$version with default features and restart" {
                # temporary replacing that mock with exit code 3010
                Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]3010 } } -ModuleName dbatools
                $splatRestart = @{
                    Version = $version
                    Path    = "TestDrive:"
                    Restart = $true
                }
                $result = Install-DbaInstance @splatRestart -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Restart-Computer -Exactly 1 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.Version | Should -Be $canonicVersion
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $true
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).FEATURES -join "," | Should -BeLike *SQLEngine*
                $result.Configuration.$($mainNode).SQLTEMPDBFILECOUNT | Should -Be 8

                # reverting the mock
                Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]0 } } -ModuleName dbatools
            }

            It "Should install tools for SQL$version" {
                Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]0 } } -ModuleName dbatools
                $splatTools = @{
                    Version = $version
                    Path    = "TestDrive:"
                    Feature = "Tools"
                }
                $result = Install-DbaInstance @splatTools -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.Version | Should -Be $canonicVersion
                $result.Successful | Should -Be $true
                "BC" | Should -BeIn $result.Configuration.$($mainNode).FEATURES
                "Conn" | Should -BeIn $result.Configuration.$($mainNode).FEATURES
                "SSMS" | Should -Not -BeIn $result.Configuration.$($mainNode).FEATURES
                "ADV_SSMS" | Should -Not -BeIn $result.Configuration.$($mainNode).FEATURES
            }
        }

        Context "SQL Server 2017" {
            BeforeAll {
                $version = "2017"
                [version]$canonicVersion = "14.0"
                $mainNode = "OPTIONS"
                # Create a dummy Configuration.ini
                @(
                    "[$mainNode]"
                    'SQLSVCACCOUNT="foo\bar"'
                    'FEATURES="SQLEngine,AS"'
                    'ACTION="Install"'
                ) | Set-Content -Path TestDrive:\Configuration.ini -Force
            }

            It "Should install SQL$version with all features enabled" {
                $result = Install-DbaInstance -Version $version -Path TestDrive: -EnableException -Confirm:$false -Feature All
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.Version | Should -Be $canonicVersion
                $result.Port | Should -Be $null
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).SQLTEMPDBFILECOUNT | Should -Be 8
            }

            It "Should install SQL$version with custom parameters" {
                $params = @{
                    SAPWD = "foo"
                }
                $splatInstall = @{
                    SqlInstance                   = "localhost\NewInstance:13337"
                    Version                       = $version
                    Path                          = "TestDrive:"
                    Configuration                 = $params
                    EngineCredential              = $cred
                    SaCredential                  = $cred
                    Port                          = 1337
                    PerformVolumeMaintenanceTasks = $true
                    AdminAccount                  = "local\foo", "local\bar"
                }
                $result = Install-DbaInstance @splatInstall -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools
                # SQLSVCINSTANTFILEINIT is used for version 2016 and later
                Assert-MockCalled -CommandName Set-DbaPrivilege -Exactly 0 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Set-DbaTcpPort -Exactly 1 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.InstanceName | Should -Be NewInstance
                $result.Version | Should -Be $canonicVersion
                $result.SACredential.GetNetworkCredential().Password | Should -Be $cred.GetNetworkCredential().Password
                $result.Port | Should -Be 1337
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).SAPWD | Should -Be "foo"
                $result.Configuration.$($mainNode).SQLSVCACCOUNT | Should -Be "foo"
                $result.Configuration.$($mainNode).SQLSYSADMINACCOUNTS | Should -Be '"local\foo" "local\bar"'
                $result.Configuration.$($mainNode).SQLTEMPDBFILECOUNT | Should -Be 8
            }

            It "Should install SQL$version with custom configuration file" {
                $splatConfig = @{
                    SqlInstance       = "localhost\NewInstance:13337"
                    Version           = $version
                    Path              = "TestDrive:"
                    ConfigurationFile = "TestDrive:\Configuration.ini"
                }
                $result = Install-DbaInstance @splatConfig -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.InstanceName | Should -Be NewInstance
                $result.Version | Should -Be $canonicVersion
                $result.Port | Should -Be 13337
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).FEATURES | Should -Be "SQLEngine,AS"
                $result.Configuration.$($mainNode).SQLSVCACCOUNT | Should -Be "foo\bar"
                $result.Configuration.$($mainNode).SQLTEMPDBFILECOUNT | Should -Be 8
            }

            It "Should install SQL$version slipstreaming the updates" {
                $result = Install-DbaInstance -Version $version -Path TestDrive: -EnableException -Confirm:$false -UpdateSourcePath TestDrive:
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.InstanceName | Should -Be MSSQLSERVER
                $result.Version | Should -Be $canonicVersion
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).UPDATESOURCE | Should -Be "TestDrive:"
                $result.Configuration.$($mainNode).UPDATEENABLED | Should -Be "True"
            }

            It "Should install SQL$version with default features and restart" {
                # temporary replacing that mock with exit code 3010
                Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]3010 } } -ModuleName dbatools
                $splatRestart = @{
                    Version = $version
                    Path    = "TestDrive:"
                    Restart = $true
                }
                $result = Install-DbaInstance @splatRestart -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Restart-Computer -Exactly 1 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.Version | Should -Be $canonicVersion
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $true
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$($mainNode).FEATURES -join "," | Should -BeLike *SQLEngine*
                $result.Configuration.$($mainNode).SQLTEMPDBFILECOUNT | Should -Be 8

                # reverting the mock
                Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]0 } } -ModuleName dbatools
            }

            It "Should install tools for SQL$version" {
                Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]0 } } -ModuleName dbatools
                $splatTools = @{
                    Version = $version
                    Path    = "TestDrive:"
                    Feature = "Tools"
                }
                $result = Install-DbaInstance @splatTools -EnableException -Confirm:$false
                Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
                Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

                $result | Should -Not -BeNullOrEmpty
                $result.Version | Should -Be $canonicVersion
                $result.Successful | Should -Be $true
                "BC" | Should -BeIn $result.Configuration.$($mainNode).FEATURES
                "Conn" | Should -BeIn $result.Configuration.$($mainNode).FEATURES
                "SSMS" | Should -Not -BeIn $result.Configuration.$($mainNode).FEATURES
                "ADV_SSMS" | Should -Not -BeIn $result.Configuration.$($mainNode).FEATURES
            }
        }
    }

    Context "Negative tests" {
        It "fails when a reboot is pending" {
            #override default mock
            Mock -CommandName Test-PendingReboot -MockWith { $true } -ModuleName dbatools
            { Install-DbaInstance -Version 2008 -Path TestDrive: -EnableException } | Should -Throw "Reboot the computer before proceeding"
            #revert default mock
            Mock -CommandName Test-PendingReboot -MockWith { $false } -ModuleName dbatools
        }
        It "fails when setup is missing in the folder" {
            $null = New-Item -Path TestDrive:\EmptyDir -ItemType Directory -Force
            { Install-DbaInstance -Version 2008 -Path TestDrive:\EmptyDir -EnableException } | Should -Throw "Failed to find setup file for SQL2008"
        }
        It "fails when repository is not available" {
            { Install-DbaInstance -Version 2008 -Path .\NonExistingFolder -EnableException } | Should -Throw "Cannot find path"
            { Install-DbaInstance -Version 2008 -EnableException } | Should -Throw "Path to SQL Server setup folder is not set"
        }
        It "fails when update execution has failed" {
            #override default mock
            Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $false; ExitCode = 12345 } } -ModuleName dbatools
            { Install-DbaInstance -Version 2008 -EnableException -Path "TestDrive:" -Confirm:$false } | Should -Throw "Installation failed with exit code 12345"
            $result = Install-DbaInstance -Version 2008 -Path "TestDrive:" -Confirm:$false -WarningVariable warVar 3>$null
            $result | Should -Not -BeNullOrEmpty
            $result.Version | Should -Be ([version]"10.0")
            $result.Successful | Should -Be $false
            $result.Restarted | Should -Be $false
            $result.Installer | Should -Be "$TestDrive\dummy.exe"
            $result.Notes | Should -BeLike "*Installation failed with exit code 12345*"
            $warVar | Should -BeLike "*Installation failed with exit code 12345*"
            #revert default mock
            Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = 0 } } -ModuleName dbatools
        }
    }
}