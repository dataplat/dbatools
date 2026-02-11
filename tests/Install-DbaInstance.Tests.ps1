#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Install-DbaInstance",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
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
                "ASAdminAccount",
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
            [PSCustomObject]@{ "Name" = "dbatoolsInstallSqlServerUpdate" ; Successful = $true ; Status = "Dummy" }
        }
        Mock -CommandName Unregister-RemoteSessionConfiguration -ModuleName dbatools -MockWith {
            [PSCustomObject]@{ "Name" = "dbatoolsInstallSqlServerUpdate" ; Successful = $true ; Status = "Dummy" }
        }
        Mock -CommandName Set-DbaPrivilege -ModuleName dbatools -MockWith { }
        Mock -CommandName Set-DbaTcpPort -ModuleName dbatools -MockWith { }
        Mock -CommandName Restart-DbaService -ModuleName dbatools -MockWith { }
        Mock -CommandName Get-DbaCmObject -ModuleName dbatools -MockWith { [PSCustomObject]@{ NumberOfLogicalProcessors = 24 } } -ParameterFilter { $ClassName -eq "Win32_processor" }
        # mock searching for setup, proper file should always it find
        Mock -CommandName Find-SqlInstanceSetup -MockWith {
            Get-ChildItem $Path -Filter "dummy.exe" -ErrorAction Stop | Select-Object -ExpandProperty FullName -First 1
        } -ModuleName dbatools
        $null = New-Item -ItemType File -Path TestDrive:\dummy.exe -Force
        $null = New-Item -ItemType File -Path TestDrive:\dummy.exe -Force
    }

    Context "Validate installs of each version" {
        BeforeAll {
            $cred = [PSCredential]::new("foo", (ConvertTo-SecureString "bar" -Force -AsPlainText))
        }

        It "Should install SQL<version> with all features enabled" -TestCases @(
            @{ version = "2008"; canonicVersion = "10.0"; mainNode = "SQLSERVER2008" }
            @{ version = "2008R2"; canonicVersion = "10.50"; mainNode = "SQLSERVER2008" }
            @{ version = "2012"; canonicVersion = "11.0"; mainNode = "OPTIONS" }
            @{ version = "2014"; canonicVersion = "12.0"; mainNode = "OPTIONS" }
            @{ version = "2016"; canonicVersion = "13.0"; mainNode = "OPTIONS" }
            @{ version = "2017"; canonicVersion = "14.0"; mainNode = "OPTIONS" }
            @{ version = "2019"; canonicVersion = "15.0"; mainNode = "OPTIONS" }
            @{ version = "2022"; canonicVersion = "16.0"; mainNode = "OPTIONS" }
            @{ version = "2025"; canonicVersion = "17.0"; mainNode = "OPTIONS" }
        ) {
            param($version, $canonicVersion, $mainNode)
            # Create a dummy Configuration.ini
            @(
                "[$mainNode]"
                "SQLSVCACCOUNT=""foo\bar"""
                "FEATURES=""SQLEngine,AS"""
                "ACTION=""Install"""
            ) | Set-Content -Path TestDrive:\Configuration.ini -Force

            $result = Install-DbaInstance -Version $version -Path TestDrive: -EnableException -Feature All
            Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
            $result.Version | Should -Be $canonicVersion
            $result.Port | Should -BeNullOrEmpty
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $false
            $result.Installer | Should -Be "$TestDrive\dummy.exe"
            $result.Notes | Should -BeNullOrEmpty
            if ($version -in "2016", "2017", "2019", "2022", "2025") {
                $result.Configuration.$mainNode.SQLTEMPDBFILECOUNT | Should -Be 8
            }
        }

        It "Should install SQL<version> with custom parameters" -TestCases @(
            @{ version = "2008"; canonicVersion = "10.0"; mainNode = "SQLSERVER2008" }
            @{ version = "2008R2"; canonicVersion = "10.50"; mainNode = "SQLSERVER2008" }
            @{ version = "2012"; canonicVersion = "11.0"; mainNode = "OPTIONS" }
            @{ version = "2014"; canonicVersion = "12.0"; mainNode = "OPTIONS" }
            @{ version = "2016"; canonicVersion = "13.0"; mainNode = "OPTIONS" }
            @{ version = "2017"; canonicVersion = "14.0"; mainNode = "OPTIONS" }
            @{ version = "2019"; canonicVersion = "15.0"; mainNode = "OPTIONS" }
            @{ version = "2022"; canonicVersion = "16.0"; mainNode = "OPTIONS" }
            @{ version = "2025"; canonicVersion = "17.0"; mainNode = "OPTIONS" }
        ) {
            param($version, $canonicVersion, $mainNode)
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
            $result = Install-DbaInstance @splatInstall -EnableException
            Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools
            if ($version -in "2008", "2008R2", "2012", "2014") {
                Assert-MockCalled -CommandName Set-DbaPrivilege -Exactly 1 -Scope It -ModuleName dbatools
            } else {
                # SQLSVCINSTANTFILEINIT is used for version 2016 and later
                Assert-MockCalled -CommandName Set-DbaPrivilege -Exactly 0 -Scope It -ModuleName dbatools
            }
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
            $result.Configuration.$mainNode.SAPWD | Should -Be "foo"
            $result.Configuration.$mainNode.SQLSVCACCOUNT | Should -Be "foo"
            $result.Configuration.$mainNode.SQLSYSADMINACCOUNTS | Should -Be """local\foo"" ""local\bar"""
            if ($version -in "2016", "2017", "2019", "2022", "2025") {
                $result.Configuration.$mainNode.SQLTEMPDBFILECOUNT | Should -Be 8
            }
        }

        It "Should install SQL<version> with custom configuration file" -TestCases @(
            @{ version = "2008"; canonicVersion = "10.0"; mainNode = "SQLSERVER2008" }
            @{ version = "2008R2"; canonicVersion = "10.50"; mainNode = "SQLSERVER2008" }
            @{ version = "2012"; canonicVersion = "11.0"; mainNode = "OPTIONS" }
            @{ version = "2014"; canonicVersion = "12.0"; mainNode = "OPTIONS" }
            @{ version = "2016"; canonicVersion = "13.0"; mainNode = "OPTIONS" }
            @{ version = "2017"; canonicVersion = "14.0"; mainNode = "OPTIONS" }
            @{ version = "2019"; canonicVersion = "15.0"; mainNode = "OPTIONS" }
            @{ version = "2022"; canonicVersion = "16.0"; mainNode = "OPTIONS" }
            @{ version = "2025"; canonicVersion = "17.0"; mainNode = "OPTIONS" }
        ) {
            param($version, $canonicVersion, $mainNode)
            # Create a dummy Configuration.ini
            @(
                "[$mainNode]"
                "SQLSVCACCOUNT=""foo\bar"""
                "FEATURES=""SQLEngine,AS"""
                "ACTION=""Install"""
            ) | Set-Content -Path TestDrive:\Configuration.ini -Force

            $splatConfig = @{
                SqlInstance       = "localhost\NewInstance:13337"
                Version           = $version
                Path              = "TestDrive:"
                ConfigurationFile = "TestDrive:\Configuration.ini"
            }
            $result = Install-DbaInstance @splatConfig -EnableException
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
            $result.Configuration.$mainNode.FEATURES | Should -Be "SQLEngine,AS"
            $result.Configuration.$mainNode.SQLSVCACCOUNT | Should -Be "foo\bar"
            if ($version -in "2016", "2017", "2019", "2022", "2025") {
                $result.Configuration.$mainNode.SQLTEMPDBFILECOUNT | Should -Be 8
            }
        }

        It "Should install SQL<version> slipstreaming the updates" -TestCases @(
            @{ version = "2008"; canonicVersion = "10.0"; mainNode = "SQLSERVER2008" }
            @{ version = "2008R2"; canonicVersion = "10.50"; mainNode = "SQLSERVER2008" }
            @{ version = "2012"; canonicVersion = "11.0"; mainNode = "OPTIONS" }
            @{ version = "2014"; canonicVersion = "12.0"; mainNode = "OPTIONS" }
            @{ version = "2016"; canonicVersion = "13.0"; mainNode = "OPTIONS" }
            @{ version = "2017"; canonicVersion = "14.0"; mainNode = "OPTIONS" }
            @{ version = "2019"; canonicVersion = "15.0"; mainNode = "OPTIONS" }
            @{ version = "2022"; canonicVersion = "16.0"; mainNode = "OPTIONS" }
            @{ version = "2025"; canonicVersion = "17.0"; mainNode = "OPTIONS" }
        ) {
            param($version, $canonicVersion, $mainNode)
            $result = Install-DbaInstance -Version $version -Path TestDrive: -EnableException -UpdateSourcePath TestDrive:
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
            $result.Configuration.$mainNode.UPDATESOURCE | Should -Be "TestDrive:"
            $result.Configuration.$mainNode.UPDATEENABLED | Should -Be "True"
        }

        It "Should install SQL<version> with default features and restart" -TestCases @(
            @{ version = "2008"; canonicVersion = "10.0"; mainNode = "SQLSERVER2008" }
            @{ version = "2008R2"; canonicVersion = "10.50"; mainNode = "SQLSERVER2008" }
            @{ version = "2012"; canonicVersion = "11.0"; mainNode = "OPTIONS" }
            @{ version = "2014"; canonicVersion = "12.0"; mainNode = "OPTIONS" }
            @{ version = "2016"; canonicVersion = "13.0"; mainNode = "OPTIONS" }
            @{ version = "2017"; canonicVersion = "14.0"; mainNode = "OPTIONS" }
            @{ version = "2019"; canonicVersion = "15.0"; mainNode = "OPTIONS" }
            @{ version = "2022"; canonicVersion = "16.0"; mainNode = "OPTIONS" }
            @{ version = "2025"; canonicVersion = "17.0"; mainNode = "OPTIONS" }
        ) {
            param($version, $canonicVersion, $mainNode)
            # temporary replacing that mock with exit code 3010
            Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]3010 } } -ModuleName dbatools
            $splatRestart = @{
                Version = $version
                Path    = "TestDrive:"
                Restart = $true
            }
            $result = Install-DbaInstance @splatRestart -EnableException
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
            $result.Configuration.$mainNode.FEATURES -join "," | Should -BeLike *SQLEngine*
            if ($version -in "2016", "2017", "2019", "2022", "2025") {
                $result.Configuration.$mainNode.SQLTEMPDBFILECOUNT | Should -Be 8
            }

            # reverting the mock
            Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]0 } } -ModuleName dbatools
        }

        It "Should install tools for SQL<version>" -TestCases @(
            @{ version = "2008"; canonicVersion = "10.0"; mainNode = "SQLSERVER2008" }
            @{ version = "2008R2"; canonicVersion = "10.50"; mainNode = "SQLSERVER2008" }
            @{ version = "2012"; canonicVersion = "11.0"; mainNode = "OPTIONS" }
            @{ version = "2014"; canonicVersion = "12.0"; mainNode = "OPTIONS" }
            @{ version = "2016"; canonicVersion = "13.0"; mainNode = "OPTIONS" }
            @{ version = "2017"; canonicVersion = "14.0"; mainNode = "OPTIONS" }
            @{ version = "2019"; canonicVersion = "15.0"; mainNode = "OPTIONS" }
            @{ version = "2022"; canonicVersion = "16.0"; mainNode = "OPTIONS" }
            @{ version = "2025"; canonicVersion = "17.0"; mainNode = "OPTIONS" }
        ) {
            param($version, $canonicVersion, $mainNode)
            Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]0 } } -ModuleName dbatools
            $splatTools = @{
                Version = $version
                Path    = "TestDrive:"
                Feature = "Tools"
            }
            $result = Install-DbaInstance @splatTools -EnableException
            Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Test-PendingReboot -Exactly 3 -Scope It -ModuleName dbatools

            $result | Should -Not -BeNullOrEmpty
            $result.Version | Should -Be $canonicVersion
            $result.Successful | Should -Be $true
            "BC" | Should -BeIn $result.Configuration.$mainNode.FEATURES
            "Conn" | Should -BeIn $result.Configuration.$mainNode.FEATURES
            if ($version -in "2008", "2008R2", "2012", "2014") {
                "SSMS" | Should -BeIn $result.Configuration.$mainNode.FEATURES
                "ADV_SSMS" | Should -BeIn $result.Configuration.$mainNode.FEATURES
            } else {
                "SSMS" | Should -Not -BeIn $result.Configuration.$mainNode.FEATURES
                "ADV_SSMS" | Should -Not -BeIn $result.Configuration.$mainNode.FEATURES
            }
        }
    }

    Context "Output validation" {
        BeforeAll {
            # Create a dummy Configuration.ini for output validation
            $mainNode = "OPTIONS"
            @(
                "[$mainNode]"
                "SQLSVCACCOUNT=""foo\bar"""
                "FEATURES=""SQLEngine,AS"""
                "ACTION=""Install"""
            ) | Set-Content -Path TestDrive:\Configuration.ini -Force

            try {
                $outputResult = Install-DbaInstance -Version 2019 -Path TestDrive: -EnableException -Feature All
            } catch {
                $outputResult = $null
            }
        }

        It "Returns output of the documented type" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $outputResult | Should -BeOfType PSCustomObject
        }

        It "Has the expected default display properties" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $outputResult.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "Version", "Port", "Successful", "Restarted", "Installer", "ExitCode", "LogFile", "Notes")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has the expected additional properties" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $additionalProps = @("SACredential", "Configuration", "ExitMessage", "Log", "ConfigurationFile")
            foreach ($prop in $additionalProps) {
                $outputResult.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }

    Context "Negative tests" {
        It "fails when a reboot is pending" {
            #override default mock
            Mock -CommandName Test-PendingReboot -MockWith { $true } -ModuleName dbatools
            { Install-DbaInstance -Version 2008 -Path TestDrive: -EnableException } | Should -Throw -ExpectedMessage "*Reboot the computer before proceeding*"
            #revert default mock
            Mock -CommandName Test-PendingReboot -MockWith { $false } -ModuleName dbatools
        }
        It "fails when setup is missing in the folder" {
            $null = New-Item -Path TestDrive:\EmptyDir -ItemType Directory -Force
            { Install-DbaInstance -Version 2008 -Path TestDrive:\EmptyDir -EnableException } | Should -Throw -ExpectedMessage "*Failed to find setup file for SQL2008*"
        }
        It "fails when repository is not available" {
            { Install-DbaInstance -Version 2008 -Path .\NonExistingFolder -EnableException } | Should -Throw -ExpectedMessage "*Cannot find path*"
            { Install-DbaInstance -Version 2008 -EnableException } | Should -Throw -ExpectedMessage "*Path to SQL Server setup folder is not set*"
        }
        It "fails when update execution has failed" {
            #override default mock
            Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $false; ExitCode = 12345 } } -ModuleName dbatools
            { Install-DbaInstance -Version 2008 -EnableException -Path "TestDrive:" } | Should -Throw -ExpectedMessage "*Installation failed with exit code 12345*"
            $result = Install-DbaInstance -Version 2008 -Path "TestDrive:" -WarningVariable warVar 3>$null
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