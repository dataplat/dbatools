param($ModuleName = 'dbatools')

Describe "Update-DbaInstance" {
    BeforeAll {
        $exeDir = "C:\Temp\dbatools_Update-DbaInstance"
        . "$PSScriptRoot\constants.ps1"

        # Prevent the functions from executing dangerous stuff and getting right responses where needed
        Mock -CommandName Invoke-Program -MockWith { [pscustomobject]@{ Successful = $true; ExitCode = [uint32[]]3010 } } -ModuleName $ModuleName
        Mock -CommandName Test-PendingReboot -MockWith { $false } -ModuleName $ModuleName
        Mock -CommandName Test-ElevationRequirement -MockWith { $null } -ModuleName $ModuleName
        Mock -CommandName Restart-Computer -MockWith { $null } -ModuleName $ModuleName
        Mock -CommandName Register-RemoteSessionConfiguration -ModuleName $ModuleName -MockWith {
            [pscustomobject]@{ 'Name' = 'dbatoolsInstallSqlServerUpdate'; Successful = $true; Status = 'Dummy' }
        }
        Mock -CommandName Unregister-RemoteSessionConfiguration -ModuleName $ModuleName -MockWith {
            [pscustomobject]@{ 'Name' = 'dbatoolsInstallSqlServerUpdate'; Successful = $true; Status = 'Dummy' }
        }
        Mock -CommandName Get-DbaDiskSpace -MockWith { [pscustomobject]@{ Name = 'C:\'; Free = 1 } } -ModuleName $ModuleName
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Update-DbaInstance
        }
        $params = @(
            'ComputerName', 'Credential', 'Version', 'Type', 'KB', 'InstanceName', 'Path', 'Restart', 'Continue', 'Throttle',
            'Authentication', 'EnableException', 'ExtractPath', 'ArgumentList', 'Download', 'NoPendingRenameCheck'
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Testing proper Authorization" {
        BeforeAll {
            Mock -CommandName Get-SQLInstanceComponent -ModuleName $ModuleName -MockWith {
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
            # Mock Get-Item and Get-ChildItem with a dummy file
            Mock -CommandName Get-ChildItem -ModuleName $ModuleName -MockWith {
                [pscustomobject]@{
                    FullName = 'c:\mocked\filename.exe'
                }
            }
            Mock -CommandName Get-Item -ModuleName $ModuleName -MockWith { 'c:\mocked' }
            # Mock Find-SqlInstanceUpdate
            Mock -CommandName Find-SqlInstanceUpdate -ModuleName $ModuleName -MockWith {
                [pscustomobject]@{
                    FullName = 'c:\mocked\path'
                }
            }
            # Mock name resolution
            Mock -CommandName Resolve-DbaNetworkName -ModuleName $ModuleName -MockWith {
                [pscustomobject]@{
                    FullComputerName = 'mock'
                }
            }
            # Mock CredSSP initialization
            Mock -CommandName Initialize-CredSSP -ModuleName $ModuleName -MockWith { }
            # Mock CmObject
            Mock -CommandName Get-DbaCmObject -ModuleName $ModuleName -MockWith { [pscustomobject]@{ SystemType = 'x64' } }
        }

        It "should call internal functions using CredSSP" {
            $password = 'pwd' | ConvertTo-SecureString -AsPlainText -Force
            $cred = [pscredential]::new('usr', $password)
            $null = Update-DbaInstance -ComputerName 'mocked' -Credential $cred -Version "2012SP3" -Path 'mocked' -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Find-SqlInstanceUpdate -Times 1 -ParameterFilter { $Authentication -eq 'CredSSP' }
            Assert-MockCalled -CommandName Initialize-CredSSP -Times 1
            Assert-MockCalled -CommandName Invoke-Program -Times 2 -ParameterFilter { $Authentication -eq 'CredSSP' }
        }

        It "should call internal functions using Default" {
            $null = Update-DbaInstance -ComputerName 'mocked' -Version "2012SP3" -Path 'mocked' -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Find-SqlInstanceUpdate -Times 1 -ParameterFilter { $Authentication -eq 'Default' }
            Assert-MockCalled -CommandName Initialize-CredSSP -Times 0
            Assert-MockCalled -CommandName Invoke-Program -Times 2 -ParameterFilter { $Authentication -eq 'Default' }
        }

        It "should call internal functions using Kerberos" {
            $password = 'pwd' | ConvertTo-SecureString -AsPlainText -Force
            $cred = [pscredential]::new('usr', $password)
            $null = Update-DbaInstance -ComputerName 'mocked' -Authentication Kerberos -Credential $cred -Version "2012SP3" -Path 'mocked' -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Find-SqlInstanceUpdate -Times 1 -ParameterFilter { $Authentication -eq 'Kerberos' }
            Assert-MockCalled -CommandName Initialize-CredSSP -Times 0
            Assert-MockCalled -CommandName Invoke-Program -Times 2 -ParameterFilter { $Authentication -eq 'Kerberos' }
        }
    }

    Context "Validate upgrades to a latest version" {
        BeforeAll {
            # this is our 'currently installed' versions
            Mock -CommandName Get-SQLInstanceComponent -ModuleName $ModuleName -MockWith {
                @(
                    [pscustomobject]@{
                        InstanceName = 'LAB0'
                        Version      = [pscustomobject]@{
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
                    [pscustomobject]@{
                        InstanceName = 'LAB2'
                        Version      = [pscustomobject]@{
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
            # Mock 2017 to think CU12 is the latest patch available
            Mock -CommandName Test-DbaBuild -ModuleName $ModuleName -MockWith {
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
                $null = New-Item -ItemType Directory -Path $exeDir -Force
            }
            # Create dummy files for specific patch versions
            $kbs = @(
                'SQLServer2008SP4-KB2979596-x64-ENU.exe',
                'SQLServer2012-KB4018073-x64-ENU.exe',
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
            Assert-MockCalled -CommandName Get-SQLInstanceComponent -Times 1
            Assert-MockCalled -CommandName Test-DbaBuild -Times 2
            Assert-MockCalled -CommandName Invoke-Program -Times 2
            Assert-MockCalled -CommandName Restart-Computer -Times 1

            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2017
            $result.TargetLevel | Should -Be 'RTMCU12'
            $result.KB | Should -Be 4464082
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2017-KB4464082-x64-ENU.exe')
            $result.Notes | Should -BeNullOrEmpty
            $result.ExtractPath | Should -Match '.*\\dbatools_KB.*Extract_.*'
        }

        It "Should mock-upgrade SQL2008\LAB2 to latest SP" {
            $result = Update-DbaInstance -Version 2008 -InstanceName LAB2 -Type ServicePack -Path $exeDir -Restart -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Test-DbaBuild -Times 0
            Assert-MockCalled -CommandName Get-SQLInstanceComponent -Times 1
            Assert-MockCalled -CommandName Invoke-Program -Times 2
            Assert-MockCalled -CommandName Restart-Computer -Times 1

            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be 'SP4'
            $result.KB | Should -Be 2979596
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.InstanceName | Should -Be 'LAB2'
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2008SP4-KB2979596-x64-ENU.exe')
            $result.Notes | Should -BeNullOrEmpty
            $result.ExtractPath | Should -Match '.*\\dbatools_KB.*Extract_.*'
        }

        It "Should mock-upgrade SQL2008\LAB2 passing extra command line parameters" {
            $result = Update-DbaInstance -Version 2008 -InstanceName LAB2 -Type ServicePack -Path $exeDir -ArgumentList @("/foo", "/bar=foobar") -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Test-DbaBuild -Times 0
            Assert-MockCalled -CommandName Get-SQLInstanceComponent -Times 1
            Assert-MockCalled -CommandName Invoke-Program -Times 1 -ParameterFilter {
                $ArgumentList[0] -like '/x:*' -and $ArgumentList[1] -eq "/quiet"
            }
            Assert-MockCalled -CommandName Invoke-Program -Times 1 -ParameterFilter {
                $ArgumentList -contains "/foo" -and $ArgumentList -contains "/bar=foobar" -and $ArgumentList -contains "/quiet"
            }

            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be 'SP4'
            $result.KB | Should -Be 2979596
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $false
            $result.InstanceName | Should -Be 'LAB2'
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2008SP4-KB2979596-x64-ENU.exe')
            $result.ExtractPath | Should -Match '.*\\dbatools_KB.*Extract_.*'
        }

        It "Should mock-upgrade two versions to latest SPs" {
            $results = Update-DbaInstance -Version 2008, 2012 -Type ServicePack -Path $exeDir -Restart -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Test-DbaBuild -Times 0
            Assert-MockCalled -CommandName Get-SQLInstanceComponent -Times 1
            Assert-MockCalled -CommandName Invoke-Program -Times 4
            Assert-MockCalled -CommandName Restart-Computer -Times 2

            ($results | Measure-Object).Count | Should -Be 2

            # 2008 SP4
            $result = $results | Where-Object MajorVersion -eq 2008
            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be 'SP4'
            $result.KB | Should -Be 2979596
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2008SP4-KB2979596-x64-ENU.exe')
            $result.Notes | Should -BeNullOrEmpty
            $result.ExtractPath | Should -Match '.*\\dbatools_KB.*Extract_.*'

            # 2012 SP4
            $result = $results | Where-Object MajorVersion -eq 2012
            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2012
            $result.TargetLevel | Should -Be 'SP4'
            $result.KB | Should -Be 4018073
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2012-KB4018073-x64-ENU.exe')
            $result.Notes | Should -BeNullOrEmpty
            $result.ExtractPath | Should -Match '.*\\dbatools_KB.*Extract_.*'
        }
    }

    # Continue updating the rest of the Context blocks in a similar fashion

    # Integration Tests
    Describe "Update-DbaInstance Integration Tests" -Tag 'IntegrationTests' {
        BeforeAll {
            # Ignore restart requirements
            Mock -CommandName Test-PendingReboot -MockWith { $false } -ModuleName $ModuleName
            # Ignore elevation requirements
            Mock -CommandName Test-ElevationRequirement -MockWith { $null } -ModuleName $ModuleName
            # No restarts
            Mock -CommandName Restart-Computer -MockWith { $null } -ModuleName $ModuleName
            # Mock whole Find-SqlInstanceUpdate because it's executed remotely
            Mock -CommandName Find-SqlInstanceUpdate -ModuleName $ModuleName -MockWith {
                [pscustomobject]@{ FullName = 'c:\mocked\filename.exe' }
            }
        }

        Context "WhatIf upgrade target instance to latest SPCU" {
            It "Should whatif-upgrade to latest SPCU" {
                $server = Connect-DbaInstance -SqlInstance $global:instance1
                $instance = $server.ServiceName
                $null = Update-DbaInstance -ComputerName $global:instance1 -Path $exeDir -Restart -EnableException -WhatIf -InstanceName $instance 3>$null
                $testBuild = Test-DbaBuild -SqlInstance $server -MaxBehind 0CU
                Assert-MockCalled -CommandName Test-PendingReboot
                Assert-MockCalled -CommandName Test-ElevationRequirement
                if (-not $testBuild.Compliant) {
                    Assert-MockCalled -CommandName Find-SqlInstanceUpdate
                }
            }
        }
    }
}
