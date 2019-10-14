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
    BeforeEach {
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
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'ComputerName', 'Action', 'Credential', 'Restart', 'Authentication', 'EnableException', 'ExtractPath'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
    Context "Validate upgrades to a latest version" {
        It "Should mock-upgrade SQL2017\LAB0 to SP0CU12 thinking it's latest" {
            $result = Invoke-DbaAdvancedUpdate -ComputerName $env:COMPUTERNAME -EnableException -Action $singleAction
            Assert-MockCalled -CommandName Invoke-Program -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 0 -Scope It -ModuleName dbatools

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
            Assert-MockCalled -CommandName Invoke-Program -Exactly 4 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 2 -Scope It -ModuleName dbatools

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
            Mock -CommandName Invoke-Program -MockWith { [pscustomobject]@{ Successful = $false; ExitCode = 12345 } } -ModuleName dbatools
            { Invoke-DbaAdvancedUpdate -ComputerName $env:COMPUTERNAME -EnableException -Action $singleAction } | Should throw 'failed with exit code 12345'
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
            Mock -CommandName Invoke-Program -MockWith { [pscustomobject]@{ Successful = $true } } -ModuleName dbatools
        }
    }
}