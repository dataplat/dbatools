param($ModuleName = 'dbatools')

Describe "Install-DbaInstance" {
    BeforeAll {
        # Prevent the functions from executing dangerous stuff and getting right responses where needed
        Mock -CommandName Invoke-Program -MockWith { [pscustomobject]@{ Successful = $true; ExitCode = [uint32[]]0 } } -ModuleName $ModuleName
        Mock -CommandName Test-PendingReboot -MockWith { $false } -ModuleName $ModuleName
        Mock -CommandName Test-ElevationRequirement -MockWith { $null } -ModuleName $ModuleName
        Mock -CommandName Restart-Computer -MockWith { $null } -ModuleName $ModuleName
        Mock -CommandName Register-RemoteSessionConfiguration -ModuleName $ModuleName -MockWith {
            [pscustomobject]@{ 'Name' = 'dbatoolsInstallSqlServerUpdate' ; Successful = $true ; Status = 'Dummy' }
        }
        Mock -CommandName Unregister-RemoteSessionConfiguration -ModuleName $ModuleName -MockWith {
            [pscustomobject]@{ 'Name' = 'dbatoolsInstallSqlServerUpdate' ; Successful = $true ; Status = 'Dummy' }
        }
        Mock -CommandName Set-DbaPrivilege -ModuleName $ModuleName -MockWith { }
        Mock -CommandName Set-DbaTcpPort -ModuleName $ModuleName -MockWith { }
        Mock -CommandName Restart-DbaService -ModuleName $ModuleName -MockWith { }
        Mock -CommandName Get-DbaCmObject -ModuleName $ModuleName -MockWith { [pscustomobject]@{NumberOfCores = 24 } } -ParameterFilter { $ClassName -eq 'Win32_processor' }
        # mock searching for setup, proper file should always it find
        Mock -CommandName Find-SqlInstanceSetup -MockWith {
            Get-ChildItem $Path -Filter "dummy.exe" -ErrorAction Stop | Select-Object -ExpandProperty FullName -First 1
        } -ModuleName $ModuleName
        $null = New-Item -ItemType File -Path TestDrive:\dummy.exe -Force
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command -Name Install-DbaInstance
        }
        It "Should have SqlInstance parameter" {
            $command | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have Version parameter" {
            $command | Should -HaveParameter Version -Type String -Mandatory:$false
        }
        It "Should have InstanceName parameter" {
            $command | Should -HaveParameter InstanceName -Type String -Mandatory:$false
        }
        It "Should have SaCredential parameter" {
            $command | Should -HaveParameter SaCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Credential parameter" {
            $command | Should -HaveParameter Credential -Type PSCredential -Mandatory:$false
        }
        It "Should have Authentication parameter" {
            $command | Should -HaveParameter Authentication -Type String -Mandatory:$false
        }
        It "Should have ConfigurationFile parameter" {
            $command | Should -HaveParameter ConfigurationFile -Type Object -Mandatory:$false
        }
        It "Should have Configuration parameter" {
            $command | Should -HaveParameter Configuration -Type Hashtable -Mandatory:$false
        }
        It "Should have Path parameter" {
            $command | Should -HaveParameter Path -Type String[] -Mandatory:$false
        }
        It "Should have Feature parameter" {
            $command | Should -HaveParameter Feature -Type String[] -Mandatory:$false
        }
        It "Should have AuthenticationMode parameter" {
            $command | Should -HaveParameter AuthenticationMode -Type String -Mandatory:$false
        }
        It "Should have InstancePath parameter" {
            $command | Should -HaveParameter InstancePath -Type String -Mandatory:$false
        }
        It "Should have DataPath parameter" {
            $command | Should -HaveParameter DataPath -Type String -Mandatory:$false
        }
        It "Should have LogPath parameter" {
            $command | Should -HaveParameter LogPath -Type String -Mandatory:$false
        }
        It "Should have TempPath parameter" {
            $command | Should -HaveParameter TempPath -Type String -Mandatory:$false
        }
        It "Should have BackupPath parameter" {
            $command | Should -HaveParameter BackupPath -Type String -Mandatory:$false
        }
        It "Should have UpdateSourcePath parameter" {
            $command | Should -HaveParameter UpdateSourcePath -Type String -Mandatory:$false
        }
        It "Should have AdminAccount parameter" {
            $command | Should -HaveParameter AdminAccount -Type String[] -Mandatory:$false
        }
        It "Should have Port parameter" {
            $command | Should -HaveParameter Port -Type Int32 -Mandatory:$false
        }
        It "Should have Throttle parameter" {
            $command | Should -HaveParameter Throttle -Type Int32 -Mandatory:$false
        }
        It "Should have ProductID parameter" {
            $command | Should -HaveParameter ProductID -Type String -Mandatory:$false
        }
        It "Should have AsCollation parameter" {
            $command | Should -HaveParameter AsCollation -Type String -Mandatory:$false
        }
        It "Should have SqlCollation parameter" {
            $command | Should -HaveParameter SqlCollation -Type String -Mandatory:$false
        }
        It "Should have EngineCredential parameter" {
            $command | Should -HaveParameter EngineCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have AgentCredential parameter" {
            $command | Should -HaveParameter AgentCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have ASCredential parameter" {
            $command | Should -HaveParameter ASCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have ISCredential parameter" {
            $command | Should -HaveParameter ISCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have RSCredential parameter" {
            $command | Should -HaveParameter RSCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have FTCredential parameter" {
            $command | Should -HaveParameter FTCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have PBEngineCredential parameter" {
            $command | Should -HaveParameter PBEngineCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have SaveConfiguration parameter" {
            $command | Should -HaveParameter SaveConfiguration -Type String -Mandatory:$false
        }
        It "Should have PerformVolumeMaintenanceTasks parameter" {
            $command | Should -HaveParameter PerformVolumeMaintenanceTasks -Type Switch -Mandatory:$false
        }
        It "Should have Restart parameter" {
            $command | Should -HaveParameter Restart -Type Switch -Mandatory:$false
        }
        It "Should have NoPendingRenameCheck parameter" {
            $command | Should -HaveParameter NoPendingRenameCheck -Type Switch -Mandatory:$false
        }
        It "Should have EnableException parameter" {
            $command | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
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
            BeforeAll {
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
                Should -Invoke Invoke-Program -Exactly 1 -Scope It -ModuleName $ModuleName
                Should -Invoke Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName $ModuleName
                Should -Invoke Test-PendingReboot -Exactly 3 -Scope It -ModuleName $ModuleName

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.Version | Should -Be $canonicVersion
                $result.Port | Should -BeNullOrEmpty
                $result.Successful | Should -BeTrue
                $result.Restarted | Should -BeFalse
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
                    AdminAccount                  = 'local\foo', 'local\bar'
                }
                $result = Install-DbaInstance @splat -EnableException -Confirm:$false
                Should -Invoke Invoke-Program -Exactly 1 -Scope It -ModuleName $ModuleName
                Should -Invoke Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName $ModuleName
                Should -Invoke Test-PendingReboot -Exactly 3 -Scope It -ModuleName $ModuleName
                if ($version -in '2008', '2008R2', '2012', '2014') {
                    Should -Invoke Set-DbaPrivilege -Exactly 1 -Scope It -ModuleName $ModuleName
                } else {
                    # SQLSVCINSTANTFILEINIT is used for version 2016 and later
                    Should -Invoke Set-DbaPrivilege -Exactly 0 -Scope It -ModuleName $ModuleName
                }
                Should -Invoke Set-DbaTcpPort -Exactly 1 -Scope It -ModuleName $ModuleName

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.InstanceName | Should -Be NewInstance
                $result.Version | Should -Be $canonicVersion
                $result.SACredential.GetNetworkCredential().Password | Should -Be $cred.GetNetworkCredential().Password
                $result.Port | Should -Be 1337
                $result.Successful | Should -BeTrue
                $result.Restarted | Should -BeFalse
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$mainNode.SAPWD | Should -Be 'foo'
                $result.Configuration.$mainNode.SQLSVCACCOUNT | Should -Be 'foo'
                $result.Configuration.$mainNode.SQLSYSADMINACCOUNTS | Should -Be '"local\foo" "local\bar"'
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
                Should -Invoke Invoke-Program -Exactly 1 -Scope It -ModuleName $ModuleName
                Should -Invoke Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName $ModuleName
                Should -Invoke Test-PendingReboot -Exactly 3 -Scope It -ModuleName $ModuleName

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.InstanceName | Should -Be NewInstance
                $result.Version | Should -Be $canonicVersion
                $result.Port | Should -Be 13337
                $result.Successful | Should -BeTrue
                $result.Restarted | Should -BeFalse
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
                Should -Invoke Invoke-Program -Exactly 1 -Scope It -ModuleName $ModuleName
                Should -Invoke Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName $ModuleName
                Should -Invoke Test-PendingReboot -Exactly 3 -Scope It -ModuleName $ModuleName

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.InstanceName | Should -Be MSSQLSERVER
                $result.Version | Should -Be $canonicVersion
                $result.Successful | Should -BeTrue
                $result.Restarted | Should -BeFalse
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$mainNode.UPDATESOURCE | Should -Be 'TestDrive:'
                $result.Configuration.$mainNode.UPDATEENABLED | Should -Be "True"
            }
            It "Should install SQL$version with default features and restart" {
                # temporary replacing that mock with exit code 3010
                Mock -CommandName Invoke-Program -MockWith { [pscustomobject]@{ Successful = $true; ExitCode = [uint32[]]3010 } } -ModuleName $ModuleName
                $splat = @{
                    Version = $version
                    Path    = 'TestDrive:'
                    Restart = $true
                }
                $result = Install-DbaInstance @splat -EnableException -Confirm:$false
                Should -Invoke Invoke-Program -Exactly 1 -Scope It -ModuleName $ModuleName
                Should -Invoke Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName $ModuleName
                Should -Invoke Test-PendingReboot -Exactly 3 -Scope It -ModuleName $ModuleName
                Should -Invoke Restart-Computer -Exactly 1 -Scope It -ModuleName $ModuleName

                $result | Should -Not -BeNullOrEmpty
                $result.ComputerName | Should -BeLike $env:COMPUTERNAME*
                $result.Version | Should -Be $canonicVersion
                $result.Successful | Should -BeTrue
                $result.Restarted | Should -BeTrue
                $result.Installer | Should -Be "$TestDrive\dummy.exe"
                $result.Notes | Should -BeNullOrEmpty
                $result.Configuration.$mainNode.FEATURES -join ',' | Should -BeLike *SQLEngine*
                if ($version -in '2016', '2017') {
                    $result.Configuration.$mainNode.SQLTEMPDBFILECOUNT | Should -Be 8
                }

                # reverting the mock
                Mock -CommandName Invoke-Program -MockWith { [pscustomobject]@{ Successful = $true; ExitCode = [uint32[]]0 } } -ModuleName $ModuleName
            }
            It "Should install tools for SQL$version" {
                Mock -CommandName Invoke-Program -MockWith { [pscustomobject]@{ Successful = $true; ExitCode = [uint32[]]0 } } -ModuleName $ModuleName
                $splat = @{
                    Version = $version
                    Path    = 'TestDrive:'
                    Feature = 'Tools'
                }
                $result = Install-DbaInstance @splat -EnableException -Confirm:$false
                Should -Invoke Invoke-Program -Exactly 1 -Scope It -ModuleName $ModuleName
                Should -Invoke Find-SqlInstanceSetup -Exactly 1 -Scope It -ModuleName $ModuleName
                Should -Invoke Test-PendingReboot -Exactly 3 -Scope It -ModuleName $ModuleName

                $result | Should -Not -BeNullOrEmpty
                $result.Version | Should -Be $canonicVersion
                $result.Successful | Should -BeTrue
                'BC' | Should -BeIn $result.Configuration.$mainNode.FEATURES
                'Conn' | Should -BeIn $result.Configuration.$mainNode.FEATURES
                if ($version -in '2008', '2008R2', '2012', '2014') {
                    'SSMS' | Should -BeIn $result.Configuration.$mainNode.FEATURES
                    'ADV_SSMS' | Should -BeIn $result.Configuration.$mainNode.FEATURES
                } else {
                    'SSMS' | Should -Not -BeIn $result.Configuration.$mainNode.FEATURES
                    'ADV_SSMS' | Should -Not -BeIn $result.Configuration.$mainNode.FEATURES
                }
            }
        }
    }
    Context "Negative tests" {
        It "fails when a reboot is pending" {
            #override default mock
            Mock -CommandName Test-PendingReboot -MockWith { $true } -ModuleName $ModuleName
            { Install-DbaInstance -Version 2008 -Path TestDrive: -EnableException } | Should -Throw 'Reboot the computer before proceeding'
            #revert default mock
            Mock -CommandName Test-PendingReboot -MockWith { $false } -ModuleName $ModuleName
        }
        It "fails when setup is missing in the folder" {
            $null = New-Item -Path TestDrive:\EmptyDir -ItemType Directory -Force
            { Install-DbaInstance -Version 2008 -Path TestDrive:\EmptyDir -EnableException } | Should -Throw 'Failed to find setup file for SQL2008'
        }
        It "fails when repository is not available" {
            { Install-DbaInstance -Version 2008 -Path .\NonExistingFolder -EnableException } | Should -Throw 'Cannot find path'
            { Install-DbaInstance -Version 2008 -EnableException } | Should -Throw 'Path to SQL Server setup folder is not set'
        }
        It "fails when update execution has failed" {
            #override default mock
            Mock -CommandName Invoke-Program -MockWith { [pscustomobject]@{ Successful = $false; ExitCode = 12345 } } -ModuleName $ModuleName
            { Install-DbaInstance -Version 2008 -EnableException -Path 'TestDrive:' -Confirm:$false } | Should -Throw 'Installation failed with exit code 12345'
            $result = Install-DbaInstance -Version 2008 -Path 'TestDrive:' -Confirm:$false -WarningVariable warVar 3>$null
            $result | Should -Not -BeNullOrEmpty
            $result.Version | Should -Be ([version]'10.0')
            $result.Successful | Should -BeFalse
            $result.Restarted | Should -BeFalse
            $result.Installer | Should -Be "$TestDrive\dummy.exe"
            $result.Notes | Should -BeLike '*Installation failed with exit code 12345*'
            $warVar | Should -BeLike '*Installation failed with exit code 12345*'
            #revert default mock
            Mock -CommandName Invoke-Program -MockWith { [pscustomobject]@{ Successful = $true; ExitCode = 0 } } -ModuleName $ModuleName
        }
    }
}
