$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

$exeDir = "C:\Temp\dbatools_$CommandName"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Prevent the functions from executing dangerous stuff and getting right responses where needed
        Mock -CommandName Invoke-Program -MockWith { [pscustomobject]@{ Successful = $true; ExitCode = [uint32[]]3010 } } -ModuleName dbatools
        Mock -CommandName Test-PendingReboot -MockWith { $false } -ModuleName dbatools
        Mock -CommandName Test-ElevationRequirement -MockWith { $null } -ModuleName dbatools
        Mock -CommandName Restart-Computer -MockWith { $null } -ModuleName dbatools
        Mock -CommandName Register-RemoteSessionConfiguration -ModuleName dbatools -MockWith {
            [pscustomobject]@{ 'Name' = 'dbatoolsInstallSqlServerUpdate' ; Successful = $true ; Status = 'Dummy' }
        }
        Mock -CommandName Unregister-RemoteSessionConfiguration -ModuleName dbatools -MockWith {
            [pscustomobject]@{ 'Name' = 'dbatoolsInstallSqlServerUpdate' ; Successful = $true ; Status = 'Dummy' }
        }
        Mock -CommandName Get-DbaDiskSpace -MockWith { [pscustomobject]@{ Name = 'C:\'; Free = 1 } } -ModuleName dbatools
    }
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'ComputerName', 'Credential', 'Version', 'Type', 'KB', 'InstanceName', 'Path', 'Restart', 'Continue', 'Throttle', 'Authentication', 'EnableException', 'ExtractPath'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
    Context "testing proper Authorization" {
        BeforeAll {
            Mock -CommandName Get-SQLInstanceComponent -ModuleName dbatools -MockWith {
                [pscustomobject]@{
                    InstanceName = 'LAB'
                    Version      = [pscustomobject]@{
                        "SqlInstance" = $null
                        "Build"       = "11.0.5058"
                        "NameLevel"   = "2012"
                        "SPLevel"     = "SP2"
                        "CULevel"     = $null
                        "KBLevel"     = "2958429"
                        "BuildLevel"  = [version]'11.0.5058'
                        "MatchType"   = "Exact"
                    }
                }
            }
            #Mock Get-Item and Get-ChildItem with a dummy file
            Mock -CommandName Get-ChildItem -ModuleName dbatools -MockWith {
                [pscustomobject]@{
                    FullName = 'c:\mocked\filename.exe'
                }
            }
            Mock -CommandName Get-Item -ModuleName dbatools -MockWith { 'c:\mocked' }
            # mock Find-SqlInstanceUpdate
            Mock -CommandName Find-SqlInstanceUpdate -ModuleName dbatools -MockWith {
                [pscustomobject]@{
                    FullName = 'c:\mocked\path'
                }
            }
            # Mock name resolution
            Mock -CommandName Resolve-DbaNetworkName -ModuleName dbatools -MockWith {
                [pscustomobject]@{
                    FullComputerName = 'mock'
                }
            }
            # Mock CredSSP initialization
            Mock -CommandName Initialize-CredSSP -ModuleName dbatools -MockWith { }
            # Mock CmObject
            Mock -CommandName Get-DbaCmObject -ModuleName dbatools -MockWith { [pscustomobject]@{ SystemType = 'x64' } }
        }
        It "should call internal functions using CredSSP" {
            $password = 'pwd' | ConvertTo-SecureString -AsPlainText -Force
            $cred = [pscredential]::new('usr', $password)
            $null = Update-DbaInstance -ComputerName 'mocked' -Credential $cred -Version "2012SP3" -Path 'mocked' -EnableException -Confirm:$false
            Assert-MockCalled -ParameterFilter { $Authentication -eq 'CredSSP' } -CommandName Find-SqlInstanceUpdate -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Initialize-CredSSP -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -ParameterFilter { $Authentication -eq 'CredSSP' } -Exactly 2 -Scope It -ModuleName dbatools
        }
        It "should call internal functions using Default" {
            $null = Update-DbaInstance -ComputerName 'mocked' -Version "2012SP3" -Path 'mocked' -EnableException -Confirm:$false
            Assert-MockCalled -ParameterFilter { $Authentication -eq 'Default' } -CommandName Find-SqlInstanceUpdate -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Initialize-CredSSP -Exactly 0 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -ParameterFilter { $Authentication -eq 'Default' } -Exactly 2 -Scope It -ModuleName dbatools
        }
        It "should call internal functions using Kerberos" {
            $password = 'pwd' | ConvertTo-SecureString -AsPlainText -Force
            $cred = [pscredential]::new('usr', $password)
            $null = Update-DbaInstance -ComputerName 'mocked' -Authentication Kerberos -Credential $cred -Version "2012SP3" -Path 'mocked' -EnableException -Confirm:$false
            Assert-MockCalled -ParameterFilter { $Authentication -eq 'Kerberos' } -CommandName Find-SqlInstanceUpdate -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Initialize-CredSSP -Exactly 0 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -ParameterFilter { $Authentication -eq 'Kerberos' } -Exactly 2 -Scope It -ModuleName dbatools
        }
    }
    Context "Validate upgrades to a latest version" {
        BeforeAll {
            #this is our 'currently installed' versions
            Mock -CommandName Get-SQLInstanceComponent -ModuleName dbatools -MockWith {
                @(
                    [pscustomobject]@{InstanceName = 'LAB0'; Version = [pscustomobject]@{
                            "SqlInstance" = $null
                            "Build"       = "14.0.3038"
                            "NameLevel"   = "2017"
                            "SPLevel"     = "RTM"
                            "CULevel"     = 'CU11'
                            "KBLevel"     = "4462262"
                            "BuildLevel"  = [version]'14.0.3038'
                            "MatchType"   = "Exact"
                        }
                    }
                    [pscustomobject]@{InstanceName = 'LAB'; Version = [pscustomobject]@{
                            "SqlInstance" = $null
                            "Build"       = "11.0.5058"
                            "NameLevel"   = "2012"
                            "SPLevel"     = "SP2"
                            "CULevel"     = $null
                            "KBLevel"     = "2958429"
                            "BuildLevel"  = [version]'11.0.5058'
                            "MatchType"   = "Exact"
                        }
                    }
                    [pscustomobject]@{InstanceName = 'LAB2'; Version = [pscustomobject]@{
                            "SqlInstance" = $null
                            "Build"       = "10.0.5770"
                            "NameLevel"   = "2008"
                            "SPLevel"     = "SP3"
                            "CULevel"     = "CU3"
                            "KBLevel"     = "2648098"
                            "BuildLevel"  = [version]'10.0.5770'
                            "MatchType"   = "Exact"
                        }
                    }
                )
            }
            #Mock 2017 to think CU12 is the latest patch available
            Mock -CommandName Test-DbaBuild -ModuleName dbatools -MockWith {
                [pscustomobject]@{
                    "Build"       = "14.0.3038"
                    "BuildTarget" = [version]"14.0.3045"
                    "Compliant"   = $false
                    "NameLevel"   = "2017"
                    "SPLevel"     = "RTM"
                    "SPTarget"    = "RTM"
                    "CULevel"     = 'CU11'
                    "CUTarget"    = 'CU12'
                    "KBLevel"     = "4462262"
                    "BuildLevel"  = [version]'14.0.3038'
                    "MatchType"   = "Exact"
                }
            } -ParameterFilter { $Build -eq [version]'14.0.3038' -and $MaxBehind -eq '0CU' }
            if (-Not(Test-Path $exeDir)) {
                $null = New-Item -ItemType Directory -Path $exeDir
            }
            #Create dummy files for specific patch versions
            $kbs = @(
                'SQLServer2008SP4-KB2979596-x64-ENU.exe'
                'SQLServer2012-KB4018073-x64-ENU.exe'
                'SQLServer2017-KB4464082-x64-ENU.exe'
            )
            foreach ($kb in $kbs) {
                $null = New-Item -ItemType File -Path (Join-Path $exeDir $kb) -Force
            }
        }
        AfterAll {
            if (Test-Path $exeDir) {
                Remove-Item $exeDir -Force -Recurse
            }
        }
        It "Should mock-upgrade SQL2017\LAB0 to SP0CU12 thinking it's latest" {
            $result = Update-DbaInstance -Version 2017 -Path $exeDir -Restart -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Get-SQLInstanceComponent -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Test-DbaBuild -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 1 -Scope It -ModuleName dbatools

            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2017
            $result.TargetLevel | Should -Be RTMCU12
            $result.KB | Should -Be 4464082
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2017-KB4464082-x64-ENU.exe')
            $result.Notes | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract_*'
        }
        It "Should mock-upgrade SQL2008\LAB2 to latest SP" {
            $result = Update-DbaInstance -Version 2008 -InstanceName LAB2 -Type ServicePack -Path $exeDir -Restart -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Test-DbaBuild -Exactly 0 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Get-SQLInstanceComponent -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 1 -Scope It -ModuleName dbatools

            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP4
            $result.KB | Should -Be 2979596
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.InstanceName | Should -Be LAB2
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2008SP4-KB2979596-x64-ENU.exe')
            $result.Notes | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract_*'
        }
        It "Should mock-upgrade two versions to latest SPs" {
            $results = Update-DbaInstance -Version 2008, 2012 -Type ServicePack -Path $exeDir -Restart -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Test-DbaBuild -Exactly 0 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Get-SQLInstanceComponent -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -Exactly 4 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 2 -Scope It -ModuleName dbatools

            ($results | Measure-Object).Count | Should -Be 2

            #2008SP4
            $result = $results | Where-Object MajorVersion -eq 2008
            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP4
            $result.KB | Should -Be 2979596
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2008SP4-KB2979596-x64-ENU.exe')
            $result.Notes | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract_*'

            #2012SP4
            $result = $results | Where-Object MajorVersion -eq 2012
            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2012
            $result.TargetLevel | Should -Be SP4
            $result.KB | Should -Be 4018073
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2012-KB4018073-x64-ENU.exe')
            $result.Notes | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract_*'
        }
    }
    Context "Validate upgrades to a specific KB" {
        BeforeAll {
            #this is our 'currently installed' versions
            Mock -CommandName Get-SQLInstanceComponent -ModuleName dbatools -MockWith {
                @(
                    [pscustomobject]@{InstanceName = 'LAB'; Version = [pscustomobject]@{
                            "SqlInstance" = $null
                            "Build"       = "13.0.4435"
                            "NameLevel"   = "2016"
                            "SPLevel"     = "SP1"
                            "CULevel"     = "CU3"
                            "KBLevel"     = "4019916"
                            "BuildLevel"  = [version]'13.0.4435'
                            "MatchType"   = "Exact"
                        }
                    }
                    [pscustomobject]@{InstanceName = 'LAB2'; Version = [pscustomobject]@{
                            "SqlInstance" = $null
                            "Build"       = "10.0.4279"
                            "NameLevel"   = "2008"
                            "SPLevel"     = "SP2"
                            "CULevel"     = "CU3"
                            "KBLevel"     = "2498535"
                            "BuildLevel"  = [version]'10.0.4279'
                            "MatchType"   = "Exact"
                        }
                    }
                )
            }
            if (-Not(Test-Path $exeDir)) {
                $null = New-Item -ItemType Directory -Path $exeDir
            }
            #Create dummy files for specific patch versions
            $kbs = @(
                'SQLServer2008SP3-KB2546951-x64-ENU.exe'
                'SQLServer2008-KB2555408-x64-ENU.exe'
                'SQLServer2008-KB2738350-x64-ENU.exe'
                'SQLServer2016-KB4040714-x64.exe'
                'SQLServer2008-KB2738350-x64-ENU.exe'
                'SQLServer2016-KB4024305-x64-ENU.exe'
            )
            foreach ($kb in $kbs) {
                $null = New-Item -ItemType File -Path (Join-Path $exeDir $kb) -Force
            }
        }
        AfterAll {
            if (Test-Path $exeDir) {
                Remove-Item $exeDir -Force -Recurse
            }
        }
        It "Should mock-upgrade SQL2008 to SP3 (KB2546951)" {
            $result = Update-DbaInstance -Kb KB2546951 -Path $exeDir -Restart -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Get-SQLInstanceComponent -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 1 -Scope It -ModuleName dbatools

            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP3
            $result.KB | Should -Be 2546951
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2008SP3-KB2546951-x64-ENU.exe')
            $result.Notes | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract_*'
        }
        It "Should mock-upgrade SQL2016 to SP1CU4 (KB3182545 + KB4024305) " {
            $result = Update-DbaInstance -Kb 3182545, 4024305 -Path $exeDir -Restart -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Get-SQLInstanceComponent -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 1 -Scope It -ModuleName dbatools

            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2016
            $result.TargetLevel | Should -Be SP1CU4
            $result.KB | Should -Be 4024305
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2016-KB4024305-x64-ENU.exe')
            $result.Notes | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract_*'
        }
        It "Should mock-upgrade both versions to different KBs" {
            $results = Update-DbaInstance -Kb 3182545, 4040714, KB2546951, KB2738350 -Path $exeDir -Restart -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Get-SQLInstanceComponent -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -Exactly 6 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 3 -Scope It -ModuleName dbatools

            ($results | Measure-Object).Count | Should -Be 3

            #2016SP1CU5
            $result = $results | Select-Object -First 1
            $result.MajorVersion | Should -Be 2016
            $result.TargetLevel | Should -Be SP1CU5
            $result.KB | Should -Be 4040714
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2016-KB4040714-x64.exe')
            $result.Notes | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract_*'

            #2008SP3
            $result = $results | Select-Object -First 1 -Skip 1
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP3
            $result.KB | Should -Be 2546951
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2008SP3-KB2546951-x64-ENU.exe')
            $result.Notes | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract_*'

            #2008SP3CU7
            $result = $results | Select-Object -First 1 -Skip 2
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP3CU7
            $result.KB | Should -Be 2738350
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2008-KB2738350-x64-ENU.exe')
            $result.Notes | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract_*'
        }
    }
    Context "Validate upgrade to the same version when installation failed" {
        BeforeAll {
            #this is our 'currently installed' versions
            Mock -CommandName Get-SQLInstanceComponent -ModuleName dbatools -MockWith {
                [pscustomobject]@{
                    InstanceName = 'LAB'
                    Version      = [pscustomobject]@{
                        "SqlInstance" = $null
                        "Build"       = "11.0.5058"
                        "NameLevel"   = "2012"
                        "SPLevel"     = "SP2"
                        "CULevel"     = $null
                        "KBLevel"     = "2958429"
                        "BuildLevel"  = [version]'11.0.5058'
                        "MatchType"   = "Exact"
                    }
                    Resume       = $true
                }
            }
            #Mock Get-Item and Get-ChildItem with a dummy file
            Mock -CommandName Get-ChildItem -ModuleName dbatools -MockWith {
                [pscustomobject]@{
                    FullName = 'c:\mocked\filename.exe'
                }
            }
            Mock -CommandName Get-Item -ModuleName dbatools -MockWith { 'c:\mocked' }
        }
        It "Should mock-upgrade interrupted setup of SQL2012 SP2" {
            $result = Update-DbaInstance -Continue -InstanceName LAB -Version 2012SP2 -Path $exeDir -Restart -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Get-SQLInstanceComponent -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 1 -Scope It -ModuleName dbatools

            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2012
            $result.TargetLevel | Should -Be SP2
            $result.KB | Should -Be 2958429
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.InstanceName | Should -Be LAB
            $result.Installer | Should -Be 'c:\mocked\filename.exe'
            $result.Notes | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract_*'
        }
    }
    Context "Should mock-upgrade to a set of specific versions" {
        BeforeAll {
            #Mock Get-Item and Get-ChildItem with a dummy file
            Mock -CommandName Get-ChildItem -ModuleName dbatools -MockWith {
                [pscustomobject]@{
                    FullName = 'c:\mocked\filename.exe'
                }
            }
            Mock -CommandName Get-Item -ModuleName dbatools -MockWith { 'c:\mocked' }
        }
        AfterAll {
        }
        $versions = @{
            '2005'   = @{
                Mock     = { [pscustomobject]@{InstanceName = 'LAB'; Version = [pscustomobject]@{
                            "SqlInstance" = $null
                            "Build"       = "9.0.1399"
                            "NameLevel"   = "2005"
                            "SPLevel"     = "RTM"
                            "CULevel"     = $null
                            "KBLevel"     = $null
                            "BuildLevel"  = [version]'9.0.1399'
                            "MatchType"   = "Exact"
                        }
                    }
                }
                Versions = @{
                    'SP1' = 0
                    'SP2' = 0
                    'SP4' = 0, 3
                }
            }
            '2008'   = @{
                Mock     = { [pscustomobject]@{InstanceName = 'LAB'; Version = [pscustomobject]@{
                            "SqlInstance" = $null
                            "Build"       = "10.0.1600"
                            "NameLevel"   = "2008"
                            "SPLevel"     = "RTM"
                            "CULevel"     = $null
                            "KBLevel"     = $null
                            "BuildLevel"  = [version]'10.0.1600'
                            "MatchType"   = "Exact"
                        }
                    }
                }
                Versions = @{
                    'SP0' = 1, 10
                    'SP1' = 0, 16
                    'SP2' = 0, 11
                    'SP3' = 0, 17
                    'SP4' = 0
                }
            }
            '2008R2' = @{
                Mock     = { [pscustomobject]@{InstanceName = 'LAB'; Version = [pscustomobject]@{
                            "SqlInstance" = $null
                            "Build"       = "10.50.1600"
                            "NameLevel"   = "2008R2"
                            "SPLevel"     = "RTM"
                            "CULevel"     = $null
                            "KBLevel"     = $null
                            "BuildLevel"  = [version]'10.50.1600'
                            "MatchType"   = "Exact"
                        }
                    }
                }
                Versions = @{
                    'SP0' = 1, 14
                    'SP1' = 0, 13
                    'SP2' = 0, 13
                    'SP3' = 0
                }
            }
            '2012'   = @{
                Mock     = { [pscustomobject]@{InstanceName = 'LAB'; Version = [pscustomobject]@{
                            "SqlInstance" = $null
                            "Build"       = "11.0.2100"
                            "NameLevel"   = "2012"
                            "SPLevel"     = "RTM"
                            "CULevel"     = $null
                            "KBLevel"     = $null
                            "BuildLevel"  = [version]'10.0.2100'
                            "MatchType"   = "Exact"
                        }
                    }
                }
                Versions = @{
                    'SP0' = 1, 11
                    'SP1' = 0, 16
                    'SP2' = 0, 16
                    'SP3' = 0, 10
                    'SP4' = 0
                }
            }
            '2014'   = @{
                Mock     = { [pscustomobject]@{InstanceName = 'LAB'; Version = [pscustomobject]@{
                            "SqlInstance" = $null
                            "Build"       = "12.0.2000"
                            "NameLevel"   = "2014"
                            "SPLevel"     = "RTM"
                            "CULevel"     = $null
                            "KBLevel"     = $null
                            "BuildLevel"  = [version]'12.0.2000'
                            "MatchType"   = "Exact"
                        }
                    }
                }
                Versions = @{
                    'SP0' = 1, 14
                    'SP1' = 0, 13
                    'SP2' = 0, 14
                    'SP3' = 0
                }
            }
            '2016'   = @{
                Mock     = { [pscustomobject]@{InstanceName = 'LAB'; Version = [pscustomobject]@{
                            "SqlInstance" = $null
                            "Build"       = "13.0.1601"
                            "NameLevel"   = "2016"
                            "SPLevel"     = "RTM"
                            "CULevel"     = $null
                            "KBLevel"     = $null
                            "BuildLevel"  = [version]'13.0.1601'
                            "MatchType"   = "Exact"
                        }
                    }
                }
                Versions = @{
                    'SP0' = 1, 9
                    'SP1' = 0, 12
                    'SP2' = 0, 4
                }
            }
            '2017'   = @{
                Mock     = { [pscustomobject]@{InstanceName = 'LAB'; Version = [pscustomobject]@{
                            "SqlInstance" = $null
                            "Build"       = "14.0.1000"
                            "NameLevel"   = "2017"
                            "SPLevel"     = "RTM"
                            "CULevel"     = $null
                            "KBLevel"     = $null
                            "BuildLevel"  = [version]'14.0.1000'
                            "MatchType"   = "Exact"
                        }
                    }
                }
                Versions = @{
                    'SP0' = 1, 12
                }
            }
        }
        foreach ($v in $versions.Keys | Sort-Object) {
            #this is our 'currently installed' versions
            Mock -CommandName Get-SQLInstanceComponent -ModuleName dbatools -MockWith $versions[$v].Mock
            #cycle through every sp and cu defined
            $upgrades = $versions[$v].Versions
            foreach ($upgrade in $upgrades.Keys | Sort-Object) {
                foreach ($cu in $upgrades[$upgrade]) {
                    $tLevel = $upgrade
                    $steps = 0
                    if ($tLevel -eq 'SP0') { $tLevel = 'RTM' }
                    else { $steps++ }
                    if ($cu -gt 0) {
                        $cuLevel = "$($tLevel)CU$cu"
                        $steps++
                    } else {
                        $cuLevel = $tLevel
                    }
                    It "$v to $cuLevel" {
                        $results = Update-DbaInstance -Version "$v$cuLevel" -Path 'mocked' -Restart -EnableException -Confirm:$false
                        Assert-MockCalled -CommandName Get-SQLInstanceComponent -Exactly 1 -Scope It -ModuleName dbatools
                        Assert-MockCalled -CommandName Invoke-Program -Exactly ($steps * 2) -Scope It -ModuleName dbatools
                        Assert-MockCalled -CommandName Restart-Computer -Exactly $steps -Scope It -ModuleName dbatools
                        for ($i = 0; $i -lt $steps; $i++) {
                            $result = $results | Select-Object -First 1 -Skip $i
                            $result | Should -Not -BeNullOrEmpty
                            $result.MajorVersion | Should -Be $v
                            if ($steps -gt 1 -and $i -eq 0) { $result.TargetLevel | Should -Be $tLevel }
                            else { $result.TargetLevel | Should -Be $cuLevel }
                            $result.KB | Should -BeGreaterThan 0
                            $result.Successful | Should -Be $true
                            $result.Restarted | Should -Be $true
                            $result.Installer | Should -Be 'c:\mocked\filename.exe'
                            $result.Notes | Should -BeNullOrEmpty
                            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract_*'
                        }
                    }
                }
            }
        }
    }
    Context "Negative tests" {
        BeforeAll {
            #this is our 'currently installed' versions
            Mock -CommandName Get-SQLInstanceComponent -ModuleName dbatools -MockWith {
                [pscustomobject]@{InstanceName = 'LAB'; Version = [pscustomobject]@{
                        "SqlInstance" = $null
                        "Build"       = "10.0.4279"
                        "NameLevel"   = "2008"
                        "SPLevel"     = "SP2"
                        "CULevel"     = "CU3"
                        "KBLevel"     = "2498535"
                        "BuildLevel"  = [version]'10.0.4279'
                        "MatchType"   = "Exact"
                    }
                }
            }
            if (-Not(Test-Path $exeDir)) {
                $null = New-Item -ItemType Directory -Path $exeDir
            }
        }
        AfterAll {
            if (Test-Path $exeDir) {
                Remove-Item $exeDir -Force -Recurse
            }
        }
        It "fails when a reboot is pending" {
            #override default mock
            Mock -CommandName Test-PendingReboot -MockWith { $true } -ModuleName dbatools
            { Update-DbaInstance -Version 2008SP3CU7 -EnableException } | Should throw 'Reboot the computer before proceeding'
            #revert default mock
            Mock -CommandName Test-PendingReboot -MockWith { $false } -ModuleName dbatools
        }
        It "fails when Version string is incorrect" {
            { Update-DbaInstance -Version '' -EnableException } | Should throw 'Cannot validate argument on parameter ''Version'''
            { Update-DbaInstance -Version $null -EnableException } | Should throw 'Cannot validate argument on parameter ''Version'''
            { Update-DbaInstance -Version SQL2008-SP3 -EnableException } | Should throw 'is an incorrect Version value'
            { Update-DbaInstance -Version SP2CU -EnableException } | Should throw 'is an incorrect Version value'
            { Update-DbaInstance -Version SPCU2 -EnableException } | Should throw 'is an incorrect Version value'
            { Update-DbaInstance -Version SQLSP2CU2 -EnableException } | Should throw 'is an incorrect Version value'
        }
        It "fails when KB is missing in the folder" {
            { Update-DbaInstance -Path $exeDir -EnableException } | Should throw 'Could not find installer for the SQL2008 update KB'
            { Update-DbaInstance -Version 2008SP3CU7 -Path $exeDir -EnableException } | Should throw 'Could not find installer for the SQL2008 update KB'
        }
        It "fails when SP level is lower than required" {
            { Update-DbaInstance -Type CumulativeUpdate -EnableException } | Should throw 'Current SP version SQL2008SP2 is not the latest available'
        }
        It "fails when repository is not available" {
            { Update-DbaInstance -Version 2008SP3CU7 -Path .\NonExistingFolder -EnableException } | Should throw 'Cannot find path'
            { Update-DbaInstance -Version 2008SP3CU7 -EnableException } | Should throw 'Path to SQL Server updates folder is not set'
        }
        It "fails when update execution has failed" {
            #Mock Get-Item and Get-ChildItem with a dummy file
            Mock -CommandName Get-ChildItem -ModuleName dbatools -MockWith {
                [pscustomobject]@{
                    FullName = 'c:\mocked\filename.exe'
                }
            }
            Mock -CommandName Get-Item -ModuleName dbatools -MockWith { 'c:\mocked' }
            #override default mock
            Mock -CommandName Invoke-Program -MockWith { [pscustomobject]@{ Successful = $false; ExitCode = 12345 } } -ModuleName dbatools
            { Update-DbaInstance -Version 2008SP3 -EnableException -Path 'mocked' -Confirm:$false } | Should throw 'failed with exit code 12345'
            $result = Update-DbaInstance -Version 2008SP3 -Path 'mocked' -Confirm:$false -WarningVariable warVar 3>$null
            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP3
            $result.KB | Should -Be 2546951
            $result.Successful | Should -Be $false
            $result.Restarted | Should -Be $false
            $result.Installer | Should -Be 'c:\mocked\filename.exe'
            $result.Notes | Should -BeLike '*failed with exit code 12345*'
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract_*'
            $warVar | Should -BeLike '*failed with exit code 12345*'
            #revert default mock
            Mock -CommandName Invoke-Program -MockWith { [pscustomobject]@{ Successful = $true } } -ModuleName dbatools
        }
    }
}

Describe "$CommandName Integration Tests" -Tag 'IntegrationTests' {
    BeforeAll {
        #ignore restart requirements
        Mock -CommandName Test-PendingReboot -MockWith { $false } -ModuleName dbatools
        #ignore elevation requirements
        Mock -CommandName Test-ElevationRequirement -MockWith { $null } -ModuleName dbatools
        #no restarts
        Mock -CommandName Restart-Computer -MockWith { $null } -ModuleName dbatools
        # mock whole Find-SqlInstanceUpdate because it's executed remotely
        Mock -CommandName Find-SqlInstanceUpdate -ModuleName dbatools -MockWith {
            [pscustomobject]@{
                FullName = 'c:\mocked\filename.exe'
            }
        }
    }
    Context "WhatIf upgrade target instance to latest SPCU" {
        It "Should whatif-upgrade to latest SPCU" {
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $instance = $server.ServiceName
            $null = Update-DbaInstance -ComputerName $script:instance1 -Path $exeDir -Restart -EnableException -WhatIf -InstanceName $instance 3>$null
            $testBuild = Test-DbaBuild -SqlInstance $server -MaxBehind 0CU
            Assert-MockCalled -CommandName Test-PendingReboot -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Test-ElevationRequirement -Scope It -ModuleName dbatools
            if ($testBuild.Compliant -eq $false) {
                Assert-MockCalled -CommandName Find-SqlInstanceUpdate -Scope It -ModuleName dbatools
            }
        }
    }
}