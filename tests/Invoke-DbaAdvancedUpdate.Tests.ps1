param($ModuleName = 'dbatools')

Describe "Invoke-DbaAdvancedUpdate" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $exeDir = "C:\Temp\dbatools_$CommandName"

        # Prevent the functions from executing dangerous stuff and getting right responses where needed
        Mock -CommandName Invoke-Program -MockWith { [pscustomobject]@{ Successful = $true; ExitCode = [uint32[]]3010 } } -ModuleName $ModuleName
        Mock -CommandName Test-PendingReboot -MockWith { $false } -ModuleName $ModuleName
        Mock -CommandName Test-ElevationRequirement -MockWith { $null } -ModuleName $ModuleName
        Mock -CommandName Restart-Computer -MockWith { $null } -ModuleName $ModuleName
        Mock -CommandName Register-RemoteSessionConfiguration -ModuleName $ModuleName -MockWith {
            [pscustomobject]@{ 'Name' = 'dbatoolsInstallSqlServerUpdate' ; Successful = $true ; Status = 'Dummy' }
        }
        Mock -CommandName Unregister-RemoteSessionConfiguration -ModuleName $ModuleName -MockWith {
            [pscustomobject]@{ 'Name' = 'dbatoolsInstallSqlServerUpdate' ; Successful = $true ; Status = 'Dummy' }
        }
        Mock -CommandName Get-DbaDiskSpace -MockWith { [pscustomobject]@{ Name = 'C:\'; Free = 1 } } -ModuleName $ModuleName
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaAdvancedUpdate
        }
        It "Should have ComputerName as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type System.String -Mandatory:$false
        }
        It "Should have Action as a non-mandatory Object[] parameter" {
            $CommandUnderTest | Should -HaveParameter Action -Type System.Object[] -Mandatory:$false
        }
        It "Should have Restart as a non-mandatory Boolean parameter" {
            $CommandUnderTest | Should -HaveParameter Restart -Type System.Boolean -Mandatory:$false
        }
        It "Should have Authentication as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Authentication -Type System.String -Mandatory:$false
        }
        It "Should have Credential as a non-mandatory PSCredential parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have ExtractPath as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter ExtractPath -Type System.String -Mandatory:$false
        }
        It "Should have ArgumentList as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter ArgumentList -Type System.String[] -Mandatory:$false
        }
        It "Should have NoPendingRenameCheck as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter NoPendingRenameCheck -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }

    Context "Validate upgrades to a latest version" {
        BeforeAll {
            $singleAction = [pscustomobject]@{
                ComputerName  = $env:COMPUTERNAME
                MajorVersion  = "2017"
                Build         = "14.0.3038"
                Architecture  = 'x64'
                TargetVersion = [pscustomobject]@{
                    "SqlInstance" = $null
                    "Build"       = "14.0.3045"
                    "NameLevel"   = "2017"
                    "SPLevel"     = "RTM", "LATEST"
                    "CULevel"     = 'CU12'
                    "KBLevel"     = "4464082"
                    "BuildLevel"  = [version]'14.0.3045'
                    "MatchType"   = "Exact"
                }
                TargetLevel   = 'RTMCU12'
                KB            = '4464082'
                Successful    = $true
                Restarted     = $false
                InstanceName  = ""
                Installer     = "dummy"
                ExtractPath   = $null
                Notes         = @()
                ExitCode      = $null
                Log           = $null
            }

            $doubleAction = @(
                [pscustomobject]@{
                    ComputerName  = $env:COMPUTERNAME
                    MajorVersion  = "2008"
                    Build         = "10.0.4279"
                    Architecture  = 'x64'
                    TargetVersion = [pscustomobject]@{
                        "SqlInstance" = $null
                        "Build"       = "10.0.5500"
                        "NameLevel"   = "2008"
                        "SPLevel"     = "SP3"
                        "CULevel"     = ''
                        "KBLevel"     = "2546951"
                        "BuildLevel"  = [version]'10.0.5500'
                        "MatchType"   = "Exact"
                    }
                    TargetLevel   = 'SP3'
                    KB            = '2546951'
                    Successful    = $true
                    Restarted     = $false
                    InstanceName  = ""
                    Installer     = "dummy"
                    ExtractPath   = $null
                    Notes         = @()
                    ExitCode      = $null
                    Log           = $null
                },
                [pscustomobject]@{
                    ComputerName  = $env:COMPUTERNAME
                    MajorVersion  = "2008"
                    Build         = "10.0.5500"
                    Architecture  = 'x64'
                    TargetVersion = [pscustomobject]@{
                        "SqlInstance" = $null
                        "Build"       = "10.0.5794"
                        "NameLevel"   = "2008"
                        "SPLevel"     = "SP3"
                        "CULevel"     = 'CU7'
                        "KBLevel"     = "2738350"
                        "BuildLevel"  = [version]'10.0.5794'
                        "MatchType"   = "Exact"
                    }
                    TargetLevel   = 'SP3CU7'
                    KB            = '2738350'
                    Successful    = $true
                    Restarted     = $false
                    InstanceName  = ""
                    Installer     = "dummy"
                    ExtractPath   = $null
                    Notes         = @()
                    ExitCode      = $null
                    Log           = $null
                }
            )
        }

        It "Should mock-upgrade SQL2017\LAB0 to SP0CU12 thinking it's latest" {
            $result = Invoke-DbaAdvancedUpdate -ComputerName $env:COMPUTERNAME -EnableException -Action $singleAction -ArgumentList @("/foo")
            Should -Invoke -CommandName Restart-Computer -Exactly 0 -Scope It -ModuleName $ModuleName
            Should -Invoke -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName $ModuleName -ParameterFilter {
                $ArgumentList[0] -like '/x:*' -and $ArgumentList[1] -eq "/quiet"
            }
            Should -Invoke -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName $ModuleName -ParameterFilter {
                $ArgumentList -contains "/foo" -and $ArgumentList -contains "/quiet"
            }

            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2017
            $result.TargetLevel | Should -Be RTMCU12
            $result.KB | Should -Be 4464082
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $false
            $result.Installer | Should -Be 'dummy'
            $result.Notes | Should -BeLike 'Restart is required for computer * to finish the installation of SQL2017RTMCU12'
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract_*'
        }

        It "Should mock-upgrade 2008 to SP3CU7" {
            $results = Invoke-DbaAdvancedUpdate -ComputerName $env:COMPUTERNAME -Restart $true -EnableException -Action $doubleAction
            Should -Invoke -CommandName Invoke-Program -Exactly 4 -Scope It -ModuleName $ModuleName
            Should -Invoke -CommandName Restart-Computer -Exactly 2 -Scope It -ModuleName $ModuleName

            ($results | Measure-Object).Count | Should -Be 2
            #2008SP3
            $result = $results | Select-Object -First 1
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP3
            $result.KB | Should -Be 2546951
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be 'dummy'
            $result.Notes | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract_*'

            #2008SP3CU7
            $result = $results | Select-Object -First 1 -Skip 1
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP3CU7
            $result.KB | Should -Be 2738350
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be 'dummy'
            $result.Notes | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract_*'
        }
    }

    Context "Negative tests" {
        It "fails when update execution has failed" {
            #override default mock
            Mock -CommandName Invoke-Program -MockWith { [pscustomobject]@{ Successful = $false; ExitCode = 12345 } } -ModuleName $ModuleName

            { Invoke-DbaAdvancedUpdate -ComputerName $env:COMPUTERNAME -EnableException -Action $singleAction } | Should -Throw 'failed with exit code 12345'

            $result = Invoke-DbaAdvancedUpdate -ComputerName $env:COMPUTERNAME -Action $singleAction -WarningVariable warVar 3>$null
            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2017
            $result.TargetLevel | Should -Be RTMCU12
            $result.KB | Should -Be 4464082
            $result.Successful | Should -Be $false
            $result.Restarted | Should -Be $false
            $result.Installer | Should -Be 'dummy'
            $result.Notes | Should -BeLike '*failed with exit code 12345*'
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract_*'
            $warVar | Should -BeLike '*failed with exit code 12345*'

            #revert default mock
            Mock -CommandName Invoke-Program -MockWith { [pscustomobject]@{ Successful = $true } } -ModuleName $ModuleName
        }
    }
}
