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
        Mock -CommandName Set-DbaPrivilege -ModuleName dbatools -MockWith {}
        Mock -CommandName Set-DbaTcpPort -ModuleName dbatools -MockWith {}
        Mock -CommandName Get-DbaCmObject -ModuleName dbatools -MockWith { [pscustomobject]@{NumberOfCores = 24} } -ParameterFilter { $ClassName -eq 'Win32_processor' }
        # mock searching for setup, proper file should always it find
        Mock -CommandName Find-SqlInstanceSetup -MockWith {
            Get-ChildItem $Path -Filter "dummy.exe" -ErrorAction Stop | Select-Object -ExpandProperty FullName -First 1
        } -ModuleName dbatools
        $null = New-Item -ItemType File -Path TestDrive:\dummy.exe -Force
    }
    Context "Validate parameters" {
        [object[]]$params = (Get-ChildItem function:\$CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = @(
            'ComputerName',
            'Version',
            'InstanceName',
            'SaCredential',
            'Credential',
            'Authentication',
            'ConfigurationPath',
            'Configuration',
            'InstallationPath',
            'Port',
            'SaveConfiguration',
            'PerformVolumeMaintenanceTasks',
            'Restart',
            'EnableException',
            'ArgumentList'
        )
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params).Count ) | Should Be 0
        }
    }
    Context "Validate installs of each version" {
        BeforeAll {
            $cred = [pscredential]::new('foo', (ConvertTo-SecureString 'bar' -Force -AsPlainText))
            $versions = @(
                [version]'10.0'
                [version]'10.50'
                [version]'11.0'
                [version]'12.0'
                [version]'13.0'
                [version]'14.0'
            )
        }
        foreach ($version in $versions) {
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
            $splat = @{
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
            It "Should install SQL $version" {
                $result = Invoke-DbaAdvancedInstall @splat -EnableException
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
    }
}