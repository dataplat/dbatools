$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Prevent the functions from executing dangerous stuff and getting right responses where needed
        Mock -CommandName Invoke-Program -MockWith { [pscustomobject]@{ Successful = $true; ExitCode = [uint32[]]0 } } -ModuleName dbatools
        Mock -CommandName Test-PendingReboot -MockWith { $false } -ModuleName dbatools
        Mock -CommandName Test-ElevationRequirement -MockWith { $null } -ModuleName dbatools
        Mock -CommandName Restart-Computer -MockWith { $null } -ModuleName dbatools
        Mock -CommandName Register-RemoteSessionConfiguration -ModuleName dbatools -MockWith {
            [pscustomobject]@{ 'Name' = 'dbatoolsInstallSqlServerUpdate' ; Successful = $true ; Status = 'Dummy' }
        }
        Mock -CommandName Unregister-RemoteSessionConfiguration -ModuleName dbatools -MockWith {
            [pscustomobject]@{ 'Name' = 'dbatoolsInstallSqlServerUpdate' ; Successful = $true ; Status = 'Dummy' }
        }
        Mock -CommandName Set-DbaPrivilege -ModuleName dbatools -MockWith { }
        Mock -CommandName Set-DbaTcpPort -ModuleName dbatools -MockWith { }
        Mock -CommandName Get-DbaCmObject -ModuleName dbatools -MockWith { [pscustomobject]@{NumberOfCores = 24 } } -ParameterFilter { $ClassName -eq 'Win32_processor' }
        # mock searching for setup, proper file should always it find
        Mock -CommandName Find-SqlInstanceSetup -MockWith {
            Get-ChildItem $Path -Filter "dummy.exe" -ErrorAction Stop | Select-Object -ExpandProperty FullName -First 1
        } -ModuleName dbatools
        $null = New-Item -ItemType File -Path TestDrive:\dummy.exe -Force
        $null = New-Item -ItemType File -Path TestDrive:\dummy.exe -Force
    }
    Context "Validate parameters" {
        [object[]]$params = (Get-ChildItem function:\$CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = @(
            'SqlInstance',
            'Version',
            'InstanceName',
            'SaCredential',
            'Credential',
            'Authentication',
            'ConfigurationFile',
            'Configuration',
            'Path',
            'Feature',
            'AuthenticationMode',
            'InstancePath',
            'DataPath',
            'LogPath',
            'TempPath',
            'BackupPath',
            'UpdateSourcePath',
            'AdminAccount',
            'Port',
            'Throttle',
            'ProductID',
            'EngineCredential',
            'AgentCredential',
            'ASCredential',
            'ISCredential',
            'RSCredential',
            'FTCredential',
            'PBEngineCredential',
            'SaveConfiguration',
            'PerformVolumeMaintenanceTasks',
            'Restart',
            'EnableException'
        )
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params).Count ) | Should Be 0
        }
    }
    Context "Validate installs of each version" {
        BeforeAll {
            $cred = [pscredential]::new('foo', (ConvertTo-SecureString 'bar' -Force -AsPlainText))
        }
        foreach ($version in '2008', '2008R2', '2012', '2014', '2016', '2017') {
            [version]$canonicVersion = switch ($version) {
                2008 { '10.0' }
                2008R2 { '10.50' }
                2012 { '11.0' }
                2014 { '12.0' }
                2016 { '13.0' }
                2017 { '14.0' }
            }
            $mainNode = if ($version -notlike '2008*') { "OPTIONS" } else { "SQLSERVER2008" }
            # Create a dummy Configuration.ini
            @(
                "[$mainNode]"
                'SQLSVCACCOUNT="foo\bar"'
                'FEATURES="SQLEngine,AS"'
            ) | Set-Content -Path TestDrive:\Configuration.ini -Force
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
                if ($version -in '2016', '2017') {
                    $result.Configuration.$mainNode.SQLTEMPDBFILECOUNT | Should -Be 8
                }
            }
            It "Should install SQL$version with custom parameters" {
                $params = @{
                    SAPWD = 'foo'
                }
                $splat = @{
                    SqlInstance                   = 'localhost\NewInstance:13337'
                    Version                       = $version
                    Path                          = 'TestDrive:'
                    Configuration                 = $params
                    EngineCredential              = $cred
                    SaCredential                  = $cred
                    Port                          = 1337
                    PerformVolumeMaintenanceTasks = $true
                }
                $result = Install-DbaInstance @splat -EnableException -Confirm:$false
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
                $result.Configuration.$mainNode.SAPWD | Should -Be 'foo'
                $result.Configuration.$mainNode.SQLSVCACCOUNT | Should -Be 'foo'
                if ($version -in '2016', '2017') {
                    $result.Configuration.$mainNode.SQLTEMPDBFILECOUNT | Should -Be 8
                }
            }
            It "Should install SQL$version with custom configuration file" {
                $splat = @{
                    SqlInstance       = 'localhost\NewInstance:13337'
                    Version           = $version
                    Path              = 'TestDrive:'
                    ConfigurationFile = 'TestDrive:\Configuration.ini'
                }
                $result = Install-DbaInstance @splat -EnableException -Confirm:$false
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
                $result.Configuration.$mainNode.FEATURES | Should -Be 'SQLEngine,AS'
                $result.Configuration.$mainNode.SQLSVCACCOUNT | Should -Be 'foo\bar'
                if ($version -in '2016', '2017') {
                    $result.Configuration.$mainNode.SQLTEMPDBFILECOUNT | Should -Be 8
                }
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
                $result.Configuration.$mainNode.UPDATESOURCE | Should -Be 'TestDrive:'
                $result.Configuration.$mainNode.UPDATEENABLED | Should -Be "True"
            }
            It "Should install SQL$version with default features and restart" {
                # temporary replacing that mock with exit code 3010
                Mock -CommandName Invoke-Program -MockWith { [pscustomobject]@{ Successful = $true; ExitCode = [uint32[]]3010 } } -ModuleName dbatools
                $splat = @{
                    Version = $version
                    Path    = 'TestDrive:'
                    Restart = $true
                }
                $result = Install-DbaInstance @splat -EnableException -Confirm:$false
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
                $result.Configuration.$mainNode.FEATURES -join ',' | Should -BeLike *SQLEngine*
                if ($version -in '2016', '2017') {
                    $result.Configuration.$mainNode.SQLTEMPDBFILECOUNT | Should -Be 8
                }

                # reverting the mock
                Mock -CommandName Invoke-Program -MockWith { [pscustomobject]@{ Successful = $true; ExitCode = [uint32[]]0 } } -ModuleName dbatools
            }
        }
    }
    Context "Negative tests" {
        It "fails when a reboot is pending" {
            #override default mock
            Mock -CommandName Test-PendingReboot -MockWith { $true } -ModuleName dbatools
            { Install-DbaInstance -Version 2008 -Path TestDrive: -EnableException } | Should throw 'Reboot the computer before proceeding'
            #revert default mock
            Mock -CommandName Test-PendingReboot -MockWith { $false } -ModuleName dbatools
        }
        It "fails when setup is missing in the folder" {
            $null = New-Item -Path TestDrive:\EmptyDir -ItemType Directory -Force
            { Install-DbaInstance -Version 2008 -Path TestDrive:\EmptyDir -EnableException } | Should throw 'Failed to find setup file for SQL2008'
        }
        It "fails when repository is not available" {
            { Install-DbaInstance -Version 2008 -Path .\NonExistingFolder -EnableException } | Should throw 'Cannot find path'
            { Install-DbaInstance -Version 2008 -EnableException } | Should throw 'Path to SQL Server setup folder is not set'
        }
        It "fails when update execution has failed" {
            #override default mock
            Mock -CommandName Invoke-Program -MockWith { [pscustomobject]@{ Successful = $false; ExitCode = 12345 } } -ModuleName dbatools
            { Install-DbaInstance -Version 2008 -EnableException -Path 'TestDrive:' -Confirm:$false } | Should throw 'Installation failed with exit code 12345'
            $result = Install-DbaInstance -Version 2008 -Path 'TestDrive:' -Confirm:$false -WarningVariable warVar 3>$null
            $result | Should -Not -BeNullOrEmpty
            $result.Version | Should -Be ([version]'10.0')
            $result.Successful | Should -Be $false
            $result.Restarted | Should -Be $false
            $result.Installer | Should -Be "$TestDrive\dummy.exe"
            $result.Notes | Should -BeLike '*Installation failed with exit code 12345*'
            $warVar | Should -BeLike '*Installation failed with exit code 12345*'
            #revert default mock
            Mock -CommandName Invoke-Program -MockWith { [pscustomobject]@{ Successful = $true; ExitCode = 0 } } -ModuleName dbatools
        }
    }
}