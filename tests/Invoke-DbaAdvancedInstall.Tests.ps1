#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaAdvancedInstall",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Version",
                "InstanceName",
                "SaCredential",
                "Credential",
                "Authentication",
                "ConfigurationPath",
                "Configuration",
                "InstallationPath",
                "Port",
                "SaveConfiguration",
                "PerformVolumeMaintenanceTasks",
                "Restart",
                "EnableException",
                "NoPendingRenameCheck",
                "ArgumentList"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # Prevent the functions from executing dangerous stuff and getting right responses where needed
        Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]0 } } -ModuleName dbatools
        Mock -CommandName Test-PendingReboot -MockWith { $false } -ModuleName dbatools
        Mock -CommandName Test-ElevationRequirement -MockWith { $null } -ModuleName dbatools
        Mock -CommandName Restart-Computer -MockWith { $null } -ModuleName dbatools
        Mock -CommandName Register-RemoteSessionConfiguration -ModuleName dbatools -MockWith {
            [PSCustomObject]@{ 'Name' = 'dbatoolsInstallSqlServerUpdate' ; Successful = $true ; Status = 'Dummy' }
        }
        Mock -CommandName Unregister-RemoteSessionConfiguration -ModuleName dbatools -MockWith {
            [PSCustomObject]@{ 'Name' = 'dbatoolsInstallSqlServerUpdate' ; Successful = $true ; Status = 'Dummy' }
        }
        Mock -CommandName Set-DbaPrivilege -ModuleName dbatools -MockWith { }
        Mock -CommandName Set-DbaTcpPort -ModuleName dbatools -MockWith { }
        Mock -CommandName Restart-DbaService -ModuleName dbatools -MockWith { }
        Mock -CommandName Get-DbaCmObject -ModuleName dbatools -MockWith { [PSCustomObject]@{NumberOfCores = 24 } } -ParameterFilter { $ClassName -eq 'Win32_processor' }
        # mock searching for setup, proper file should always it find
        Mock -CommandName Find-SqlInstanceSetup -MockWith {
            Get-ChildItem $Path -Filter "dummy.exe" -ErrorAction Stop | Select-Object -ExpandProperty FullName -First 1
        } -ModuleName dbatools
        $null = New-Item -ItemType File -Path TestDrive:\dummy.exe -Force
    }

    Context "SQL Server version 10.0 install validation" {
        It "Should install SQL 10.0" {
            $version = [version]'10.0'
            $cred = New-Object PSCredential('foo', (ConvertTo-SecureString 'bar' -Force -AsPlainText))
            $mainNode = if ($version.Major -ne 10) { "OPTIONS" } else { "SQLSERVER2008" }

            # Create a dummy Configuration.ini
            @(
                "[$mainNode]"
                'SQLSVCACCOUNT="foo\bar"'
                'FEATURES="SQLEngine,AS"'
            ) | Set-Content -Path TestDrive:\Configuration.ini -Force

            $config = @{
                $mainNode = @{
                    ACTION                = "Install"
                    AGTSVCSTARTUPTYPE     = "Automatic"
                    ASCOLLATION           = "Latin1_General_CI_AS"
                    BROWSERSVCSTARTUPTYPE = "False"
                    ENABLERANU            = "False"
                    ERRORREPORTING        = "False"
                    FEATURES              = "SQLEngine"
                    FILESTREAMLEVEL       = "0"
                    HELP                  = "False"
                    INDICATEPROGRESS      = "False"
                    INSTANCEID            = 'foo'
                    INSTANCENAME          = 'foo'
                    ISSVCSTARTUPTYPE      = "Automatic"
                    QUIET                 = "True"
                    QUIETSIMPLE           = "False"
                    RSINSTALLMODE         = "DefaultNativeMode"
                    RSSVCSTARTUPTYPE      = "Automatic"
                    SQLCOLLATION          = "SQL_Latin1_General_CP1_CI_AS"
                    SQLSVCSTARTUPTYPE     = "Automatic"
                    SQLSYSADMINACCOUNTS   = 'foo\bar'
                    SQMREPORTING          = "False"
                    TCPENABLED            = "1"
                    UPDATEENABLED         = "False"
                    X86                   = "False"
                }
            }

            $splatInstall = @{
                ComputerName                  = $env:COMPUTERNAME
                InstanceName                  = 'foo'
                Port                          = 1337
                InstallationPath              = 'TestDrive:\dummy.exe'
                ConfigurationPath             = 'TestDrive:\Configuration.ini'
                ArgumentList                  = @('/IACCEPTSQLSERVERLICENSETERMS')
                Restart                       = $false
                Version                       = $version
                Configuration                 = $config
                SaveConfiguration             = 'TestDrive:\Configuration.copy.ini'
                SaCredential                  = $cred
                PerformVolumeMaintenanceTasks = $true
            }
            $result = Invoke-DbaAdvancedInstall @splatInstall -EnableException -OutVariable "global:dbatoolsciOutput"
            Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Test-PendingReboot -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Set-DbaPrivilege -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Set-DbaTcpPort -Exactly 1 -Scope It -ModuleName dbatools

            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
            $result.InstanceName | Should -Be 'foo'
            $result.Version | Should -Be $version
            $result.SACredential.GetNetworkCredential().Password | Should -Be $cred.GetNetworkCredential().Password
            $result.Port | Should -Be 1337
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $false
            $result.Installer | Should -Be 'TestDrive:\dummy.exe'
            $result.Notes | Should -BeNullOrEmpty
        }
    }

    Context "SQL Server version 10.50 install validation" {
        It "Should install SQL 10.50" {
            $version = [version]'10.50'
            $cred = New-Object PSCredential('foo', (ConvertTo-SecureString 'bar' -Force -AsPlainText))
            $mainNode = if ($version.Major -ne 10) { "OPTIONS" } else { "SQLSERVER2008" }

            # Create a dummy Configuration.ini
            @(
                "[$mainNode]"
                'SQLSVCACCOUNT="foo\bar"'
                'FEATURES="SQLEngine,AS"'
            ) | Set-Content -Path TestDrive:\Configuration.ini -Force

            $config = @{
                $mainNode = @{
                    ACTION                = "Install"
                    AGTSVCSTARTUPTYPE     = "Automatic"
                    ASCOLLATION           = "Latin1_General_CI_AS"
                    BROWSERSVCSTARTUPTYPE = "False"
                    ENABLERANU            = "False"
                    ERRORREPORTING        = "False"
                    FEATURES              = "SQLEngine"
                    FILESTREAMLEVEL       = "0"
                    HELP                  = "False"
                    INDICATEPROGRESS      = "False"
                    INSTANCEID            = 'foo'
                    INSTANCENAME          = 'foo'
                    ISSVCSTARTUPTYPE      = "Automatic"
                    QUIET                 = "True"
                    QUIETSIMPLE           = "False"
                    RSINSTALLMODE         = "DefaultNativeMode"
                    RSSVCSTARTUPTYPE      = "Automatic"
                    SQLCOLLATION          = "SQL_Latin1_General_CP1_CI_AS"
                    SQLSVCSTARTUPTYPE     = "Automatic"
                    SQLSYSADMINACCOUNTS   = 'foo\bar'
                    SQMREPORTING          = "False"
                    TCPENABLED            = "1"
                    UPDATEENABLED         = "False"
                    X86                   = "False"
                }
            }

            $splatInstall = @{
                ComputerName                  = $env:COMPUTERNAME
                InstanceName                  = 'foo'
                Port                          = 1337
                InstallationPath              = 'TestDrive:\dummy.exe'
                ConfigurationPath             = 'TestDrive:\Configuration.ini'
                ArgumentList                  = @('/IACCEPTSQLSERVERLICENSETERMS')
                Restart                       = $false
                Version                       = $version
                Configuration                 = $config
                SaveConfiguration             = 'TestDrive:\Configuration.copy.ini'
                SaCredential                  = $cred
                PerformVolumeMaintenanceTasks = $true
            }
            $result = Invoke-DbaAdvancedInstall @splatInstall -EnableException
            Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Test-PendingReboot -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Set-DbaPrivilege -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Set-DbaTcpPort -Exactly 1 -Scope It -ModuleName dbatools

            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
            $result.InstanceName | Should -Be 'foo'
            $result.Version | Should -Be $version
            $result.SACredential.GetNetworkCredential().Password | Should -Be $cred.GetNetworkCredential().Password
            $result.Port | Should -Be 1337
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $false
            $result.Installer | Should -Be 'TestDrive:\dummy.exe'
            $result.Notes | Should -BeNullOrEmpty
        }
    }

    Context "SQL Server version 11.0 install validation" {
        It "Should install SQL 11.0" {
            $version = [version]'11.0'
            $cred = New-Object PSCredential('foo', (ConvertTo-SecureString 'bar' -Force -AsPlainText))
            $mainNode = if ($version.Major -ne 10) { "OPTIONS" } else { "SQLSERVER2008" }

            # Create a dummy Configuration.ini
            @(
                "[$mainNode]"
                'SQLSVCACCOUNT="foo\bar"'
                'FEATURES="SQLEngine,AS"'
            ) | Set-Content -Path TestDrive:\Configuration.ini -Force

            $config = @{
                $mainNode = @{
                    ACTION                = "Install"
                    AGTSVCSTARTUPTYPE     = "Automatic"
                    ASCOLLATION           = "Latin1_General_CI_AS"
                    BROWSERSVCSTARTUPTYPE = "False"
                    ENABLERANU            = "False"
                    ERRORREPORTING        = "False"
                    FEATURES              = "SQLEngine"
                    FILESTREAMLEVEL       = "0"
                    HELP                  = "False"
                    INDICATEPROGRESS      = "False"
                    INSTANCEID            = 'foo'
                    INSTANCENAME          = 'foo'
                    ISSVCSTARTUPTYPE      = "Automatic"
                    QUIET                 = "True"
                    QUIETSIMPLE           = "False"
                    RSINSTALLMODE         = "DefaultNativeMode"
                    RSSVCSTARTUPTYPE      = "Automatic"
                    SQLCOLLATION          = "SQL_Latin1_General_CP1_CI_AS"
                    SQLSVCSTARTUPTYPE     = "Automatic"
                    SQLSYSADMINACCOUNTS   = 'foo\bar'
                    SQMREPORTING          = "False"
                    TCPENABLED            = "1"
                    UPDATEENABLED         = "False"
                    X86                   = "False"
                }
            }

            $splatInstall = @{
                ComputerName                  = $env:COMPUTERNAME
                InstanceName                  = 'foo'
                Port                          = 1337
                InstallationPath              = 'TestDrive:\dummy.exe'
                ConfigurationPath             = 'TestDrive:\Configuration.ini'
                ArgumentList                  = @('/IACCEPTSQLSERVERLICENSETERMS')
                Restart                       = $false
                Version                       = $version
                Configuration                 = $config
                SaveConfiguration             = 'TestDrive:\Configuration.copy.ini'
                SaCredential                  = $cred
                PerformVolumeMaintenanceTasks = $true
            }
            $result = Invoke-DbaAdvancedInstall @splatInstall -EnableException
            Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Test-PendingReboot -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Set-DbaPrivilege -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Set-DbaTcpPort -Exactly 1 -Scope It -ModuleName dbatools

            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
            $result.InstanceName | Should -Be 'foo'
            $result.Version | Should -Be $version
            $result.SACredential.GetNetworkCredential().Password | Should -Be $cred.GetNetworkCredential().Password
            $result.Port | Should -Be 1337
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $false
            $result.Installer | Should -Be 'TestDrive:\dummy.exe'
            $result.Notes | Should -BeNullOrEmpty
        }
    }

    Context "SQL Server version 12.0 install validation" {
        It "Should install SQL 12.0" {
            $version = [version]'12.0'
            $cred = New-Object PSCredential('foo', (ConvertTo-SecureString 'bar' -Force -AsPlainText))
            $mainNode = if ($version.Major -ne 10) { "OPTIONS" } else { "SQLSERVER2008" }

            # Create a dummy Configuration.ini
            @(
                "[$mainNode]"
                'SQLSVCACCOUNT="foo\bar"'
                'FEATURES="SQLEngine,AS"'
            ) | Set-Content -Path TestDrive:\Configuration.ini -Force

            $config = @{
                $mainNode = @{
                    ACTION                = "Install"
                    AGTSVCSTARTUPTYPE     = "Automatic"
                    ASCOLLATION           = "Latin1_General_CI_AS"
                    BROWSERSVCSTARTUPTYPE = "False"
                    ENABLERANU            = "False"
                    ERRORREPORTING        = "False"
                    FEATURES              = "SQLEngine"
                    FILESTREAMLEVEL       = "0"
                    HELP                  = "False"
                    INDICATEPROGRESS      = "False"
                    INSTANCEID            = 'foo'
                    INSTANCENAME          = 'foo'
                    ISSVCSTARTUPTYPE      = "Automatic"
                    QUIET                 = "True"
                    QUIETSIMPLE           = "False"
                    RSINSTALLMODE         = "DefaultNativeMode"
                    RSSVCSTARTUPTYPE      = "Automatic"
                    SQLCOLLATION          = "SQL_Latin1_General_CP1_CI_AS"
                    SQLSVCSTARTUPTYPE     = "Automatic"
                    SQLSYSADMINACCOUNTS   = 'foo\bar'
                    SQMREPORTING          = "False"
                    TCPENABLED            = "1"
                    UPDATEENABLED         = "False"
                    X86                   = "False"
                }
            }

            $splatInstall = @{
                ComputerName                  = $env:COMPUTERNAME
                InstanceName                  = 'foo'
                Port                          = 1337
                InstallationPath              = 'TestDrive:\dummy.exe'
                ConfigurationPath             = 'TestDrive:\Configuration.ini'
                ArgumentList                  = @('/IACCEPTSQLSERVERLICENSETERMS')
                Restart                       = $false
                Version                       = $version
                Configuration                 = $config
                SaveConfiguration             = 'TestDrive:\Configuration.copy.ini'
                SaCredential                  = $cred
                PerformVolumeMaintenanceTasks = $true
            }
            $result = Invoke-DbaAdvancedInstall @splatInstall -EnableException
            Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Test-PendingReboot -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Set-DbaPrivilege -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Set-DbaTcpPort -Exactly 1 -Scope It -ModuleName dbatools

            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
            $result.InstanceName | Should -Be 'foo'
            $result.Version | Should -Be $version
            $result.SACredential.GetNetworkCredential().Password | Should -Be $cred.GetNetworkCredential().Password
            $result.Port | Should -Be 1337
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $false
            $result.Installer | Should -Be 'TestDrive:\dummy.exe'
            $result.Notes | Should -BeNullOrEmpty
        }
    }

    Context "SQL Server version 13.0 install validation" {
        It "Should install SQL 13.0" {
            $version = [version]'13.0'
            $cred = New-Object PSCredential('foo', (ConvertTo-SecureString 'bar' -Force -AsPlainText))
            $mainNode = if ($version.Major -ne 10) { "OPTIONS" } else { "SQLSERVER2008" }

            # Create a dummy Configuration.ini
            @(
                "[$mainNode]"
                'SQLSVCACCOUNT="foo\bar"'
                'FEATURES="SQLEngine,AS"'
            ) | Set-Content -Path TestDrive:\Configuration.ini -Force

            $config = @{
                $mainNode = @{
                    ACTION                = "Install"
                    AGTSVCSTARTUPTYPE     = "Automatic"
                    ASCOLLATION           = "Latin1_General_CI_AS"
                    BROWSERSVCSTARTUPTYPE = "False"
                    ENABLERANU            = "False"
                    ERRORREPORTING        = "False"
                    FEATURES              = "SQLEngine"
                    FILESTREAMLEVEL       = "0"
                    HELP                  = "False"
                    INDICATEPROGRESS      = "False"
                    INSTANCEID            = 'foo'
                    INSTANCENAME          = 'foo'
                    ISSVCSTARTUPTYPE      = "Automatic"
                    QUIET                 = "True"
                    QUIETSIMPLE           = "False"
                    RSINSTALLMODE         = "DefaultNativeMode"
                    RSSVCSTARTUPTYPE      = "Automatic"
                    SQLCOLLATION          = "SQL_Latin1_General_CP1_CI_AS"
                    SQLSVCSTARTUPTYPE     = "Automatic"
                    SQLSYSADMINACCOUNTS   = 'foo\bar'
                    SQMREPORTING          = "False"
                    TCPENABLED            = "1"
                    UPDATEENABLED         = "False"
                    X86                   = "False"
                }
            }

            $splatInstall = @{
                ComputerName                  = $env:COMPUTERNAME
                InstanceName                  = 'foo'
                Port                          = 1337
                InstallationPath              = 'TestDrive:\dummy.exe'
                ConfigurationPath             = 'TestDrive:\Configuration.ini'
                ArgumentList                  = @('/IACCEPTSQLSERVERLICENSETERMS')
                Restart                       = $false
                Version                       = $version
                Configuration                 = $config
                SaveConfiguration             = 'TestDrive:\Configuration.copy.ini'
                SaCredential                  = $cred
                PerformVolumeMaintenanceTasks = $true
            }
            $result = Invoke-DbaAdvancedInstall @splatInstall -EnableException
            Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Test-PendingReboot -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Set-DbaPrivilege -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Set-DbaTcpPort -Exactly 1 -Scope It -ModuleName dbatools

            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
            $result.InstanceName | Should -Be 'foo'
            $result.Version | Should -Be $version
            $result.SACredential.GetNetworkCredential().Password | Should -Be $cred.GetNetworkCredential().Password
            $result.Port | Should -Be 1337
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $false
            $result.Installer | Should -Be 'TestDrive:\dummy.exe'
            $result.Notes | Should -BeNullOrEmpty
        }
    }

    Context "SQL Server version 14.0 install validation" {
        It "Should install SQL 14.0" {
            $version = [version]'14.0'
            $cred = New-Object PSCredential('foo', (ConvertTo-SecureString 'bar' -Force -AsPlainText))
            $mainNode = if ($version.Major -ne 10) { "OPTIONS" } else { "SQLSERVER2008" }

            # Create a dummy Configuration.ini
            @(
                "[$mainNode]"
                'SQLSVCACCOUNT="foo\bar"'
                'FEATURES="SQLEngine,AS"'
            ) | Set-Content -Path TestDrive:\Configuration.ini -Force

            $config = @{
                $mainNode = @{
                    ACTION                = "Install"
                    AGTSVCSTARTUPTYPE     = "Automatic"
                    ASCOLLATION           = "Latin1_General_CI_AS"
                    BROWSERSVCSTARTUPTYPE = "False"
                    ENABLERANU            = "False"
                    ERRORREPORTING        = "False"
                    FEATURES              = "SQLEngine"
                    FILESTREAMLEVEL       = "0"
                    HELP                  = "False"
                    INDICATEPROGRESS      = "False"
                    INSTANCEID            = 'foo'
                    INSTANCENAME          = 'foo'
                    ISSVCSTARTUPTYPE      = "Automatic"
                    QUIET                 = "True"
                    QUIETSIMPLE           = "False"
                    RSINSTALLMODE         = "DefaultNativeMode"
                    RSSVCSTARTUPTYPE      = "Automatic"
                    SQLCOLLATION          = "SQL_Latin1_General_CP1_CI_AS"
                    SQLSVCSTARTUPTYPE     = "Automatic"
                    SQLSYSADMINACCOUNTS   = 'foo\bar'
                    SQMREPORTING          = "False"
                    TCPENABLED            = "1"
                    UPDATEENABLED         = "False"
                    X86                   = "False"
                }
            }

            $splatInstall = @{
                ComputerName                  = $env:COMPUTERNAME
                InstanceName                  = 'foo'
                Port                          = 1337
                InstallationPath              = 'TestDrive:\dummy.exe'
                ConfigurationPath             = 'TestDrive:\Configuration.ini'
                ArgumentList                  = @('/IACCEPTSQLSERVERLICENSETERMS')
                Restart                       = $false
                Version                       = $version
                Configuration                 = $config
                SaveConfiguration             = 'TestDrive:\Configuration.copy.ini'
                SaCredential                  = $cred
                PerformVolumeMaintenanceTasks = $true
            }
            $result = Invoke-DbaAdvancedInstall @splatInstall -EnableException
            Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Test-PendingReboot -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Set-DbaPrivilege -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Set-DbaTcpPort -Exactly 1 -Scope It -ModuleName dbatools

            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
            $result.InstanceName | Should -Be 'foo'
            $result.Version | Should -Be $version
            $result.SACredential.GetNetworkCredential().Password | Should -Be $cred.GetNetworkCredential().Password
            $result.Port | Should -Be 1337
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $false
            $result.Installer | Should -Be 'TestDrive:\dummy.exe'
            $result.Notes | Should -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "Version",
                "SACredential",
                "Successful",
                "Restarted",
                "Configuration",
                "InstanceName",
                "Installer",
                "Port",
                "Notes",
                "ExitCode",
                "ExitMessage",
                "Log",
                "LogFile",
                "ConfigurationFile"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "Version",
                "Port",
                "Successful",
                "Restarted",
                "Installer",
                "ExitCode",
                "LogFile",
                "Notes"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}