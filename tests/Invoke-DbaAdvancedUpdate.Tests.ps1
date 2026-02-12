#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaAdvancedUpdate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Action",
                "Restart",
                "Authentication",
                "Credential",
                "ExtractPath",
                "ArgumentList",
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
        Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true; ExitCode = [uint32[]]3010 } } -ModuleName dbatools
        Mock -CommandName Test-PendingReboot -MockWith { $false } -ModuleName dbatools
        Mock -CommandName Test-ElevationRequirement -MockWith { $null } -ModuleName dbatools
        Mock -CommandName Restart-Computer -MockWith { $null } -ModuleName dbatools
        Mock -CommandName Register-RemoteSessionConfiguration -ModuleName dbatools -MockWith {
            [PSCustomObject]@{ "Name" = "dbatoolsInstallSqlServerUpdate" ; Successful = $true ; Status = "Dummy" }
        }
        Mock -CommandName Unregister-RemoteSessionConfiguration -ModuleName dbatools -MockWith {
            [PSCustomObject]@{ "Name" = "dbatoolsInstallSqlServerUpdate" ; Successful = $true ; Status = "Dummy" }
        }
        Mock -CommandName Get-DbaDiskSpace -MockWith { [PSCustomObject]@{ Name = "C:\"; Free = 1 } } -ModuleName dbatools
    }

    BeforeEach {
        $singleAction = [PSCustomObject]@{
            ComputerName  = $env:COMPUTERNAME
            MajorVersion  = "2017"
            Build         = "14.0.3038"
            Architecture  = "x64"
            TargetVersion = [PSCustomObject]@{
                "SqlInstance" = $null
                "Build"       = "14.0.3045"
                "NameLevel"   = "2017"
                "SPLevel"     = "RTM", "LATEST"
                "CULevel"     = "CU12"
                "KBLevel"     = "4464082"
                "BuildLevel"  = [version]"14.0.3045"
                "MatchType"   = "Exact"
            }
            TargetLevel   = "RTMCU12"
            KB            = "4464082"
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
            [PSCustomObject]@{
                ComputerName  = $env:COMPUTERNAME
                MajorVersion  = "2008"
                Build         = "10.0.4279"
                Architecture  = "x64"
                TargetVersion = [PSCustomObject]@{
                    "SqlInstance" = $null
                    "Build"       = "10.0.5500"
                    "NameLevel"   = "2008"
                    "SPLevel"     = "SP3"
                    "CULevel"     = ""
                    "KBLevel"     = "2546951"
                    "BuildLevel"  = [version]"10.0.5500"
                    "MatchType"   = "Exact"
                }
                TargetLevel   = "SP3"
                KB            = "2546951"
                Successful    = $true
                Restarted     = $false
                InstanceName  = ""
                Installer     = "dummy"
                ExtractPath   = $null
                Notes         = @()
                ExitCode      = $null
                Log           = $null
            }
            [PSCustomObject]@{
                ComputerName  = $env:COMPUTERNAME
                MajorVersion  = "2008"
                Build         = "10.0.5500"
                Architecture  = "x64"
                TargetVersion = [PSCustomObject]@{
                    "SqlInstance" = $null
                    "Build" = "10.0.5794"
                    "NameLevel" = "2008"
                    "SPLevel" = "SP3"
                    "CULevel" = "CU7"
                    "KBLevel" = "2738350"
                    "BuildLevel" = [version]"10.0.5794"
                    "MatchType" = "Exact"
                }
                TargetLevel   = "SP3CU7"
                KB            = "2738350"
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

    Context "Validate upgrades to a latest version" {
        It "Should mock-upgrade SQL2017\LAB0 to SP0CU12 thinking it's latest" {
            $result = Invoke-DbaAdvancedUpdate -ComputerName $env:COMPUTERNAME -EnableException -Action $singleAction -ArgumentList @("/foo")
            Assert-MockCalled -CommandName Restart-Computer -Exactly 0 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools -ParameterFilter {
                if ($ArgumentList[0] -like "/x:*" -and $ArgumentList[1] -eq "/quiet") { return $true }
            }
            Assert-MockCalled -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools -ParameterFilter {
                Write-Host $ArgumentList
                if ($ArgumentList -contains "/foo" -and $ArgumentList -contains "/quiet") { return $true }
            }

            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2017
            $result.TargetLevel | Should -Be RTMCU12
            $result.KB | Should -Be 4464082
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $false
            $result.Installer | Should -Be "dummy"
            $result.Notes | Should -BeLike "Restart is required for computer * to finish the installation of SQL2017RTMCU12"
            $result.ExtractPath | Should -BeLike "*\dbatools_KB*Extract_*"

            # Output validation
            $expectedProperties = @(
                "TargetLevel",
                "KB",
                "Installer",
                "MajorVersion",
                "Build",
                "InstanceName",
                "Successful",
                "Restarted",
                "ExitCode",
                "ExtractPath",
                "Log",
                "Notes"
            )
            foreach ($prop in $expectedProperties) {
                $result.psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
        It "Should mock-upgrade 2008 to SP3CU7" {
            $results = Invoke-DbaAdvancedUpdate -ComputerName $env:COMPUTERNAME -Restart $true -EnableException -Action $doubleAction
            Assert-MockCalled -CommandName Invoke-Program -Exactly 4 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 2 -Scope It -ModuleName dbatools

            $results.Count | Should -BeExactly 2
            #2008SP3
            $result = $results | Select-Object -First 1
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP3
            $result.KB | Should -Be 2546951
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be "dummy"
            $result.Notes | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike "*\dbatools_KB*Extract_*"

            #2008SP3CU7
            $result = $results | Select-Object -First 1 -Skip 1
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP3CU7
            $result.KB | Should -Be 2738350
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be "dummy"
            $result.Notes | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike "*\dbatools_KB*Extract_*"
        }
    }

    Context "Negative tests" {
        It "fails when update execution has failed" {
            #override default mock
            Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $false; ExitCode = 12345 } } -ModuleName dbatools
            { Invoke-DbaAdvancedUpdate -ComputerName $env:COMPUTERNAME -EnableException -Action $singleAction } | Should -Throw -ExpectedMessage "*failed with exit code 12345*"
            $result = Invoke-DbaAdvancedUpdate -ComputerName $env:COMPUTERNAME -Action $singleAction -WarningVariable warVar 3>$null
            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2017
            $result.TargetLevel | Should -Be RTMCU12
            $result.KB | Should -Be 4464082
            $result.Successful | Should -Be $false
            $result.Restarted | Should -Be $false
            $result.Installer | Should -Be "dummy"
            $result.Notes | Should -BeLike "*failed with exit code 12345*"
            $result.ExtractPath | Should -BeLike "*\dbatools_KB*Extract_*"
            $warVar | Should -BeLike "*failed with exit code 12345*"
            #revert default mock
            Mock -CommandName Invoke-Program -MockWith { [PSCustomObject]@{ Successful = $true } } -ModuleName dbatools
        }
    }
}
