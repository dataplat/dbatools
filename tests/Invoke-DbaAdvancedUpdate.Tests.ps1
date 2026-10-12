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
            Should -Invoke -CommandName Restart-Computer -Exactly 0 -Scope It -ModuleName dbatools
            Should -Invoke -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools -ParameterFilter {
                if ($ArgumentList[0] -like "/x:*" -and $ArgumentList[1] -eq "/quiet") { return $true }
            }
            Should -Invoke -CommandName Invoke-Program -Exactly 1 -Scope It -ModuleName dbatools -ParameterFilter {
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
        }
        It "Should mock-upgrade 2008 to SP3CU7" {
            $results = Invoke-DbaAdvancedUpdate -ComputerName $env:COMPUTERNAME -Restart $true -EnableException -Action $doubleAction
            Should -Invoke -CommandName Invoke-Program -Exactly 4 -Scope It -ModuleName dbatools
            Should -Invoke -CommandName Restart-Computer -Exactly 2 -Scope It -ModuleName dbatools

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

    Context "When the installer cannot be started" {
        BeforeAll {
            # The command runs in a runspace of its own, created by the PowerShell API without a host. There
            # Write-Progress puts every record into Streams.Progress, so a bar that was never completed shows
            # as an Id whose last record is not a completed one. The runspace imports its own copy of the
            # module, so the mocks above do not reach it: this is the real command on the local computer. The
            # installer does not exist, so the extraction fails and nothing is installed.
            $missingUpdateAction = [PSCustomObject]@{
                ComputerName = $env:COMPUTERNAME
                MajorVersion = "2022"
                Build        = "16.0.1000"
                Architecture = "x64"
                TargetLevel  = "CU1"
                KB           = "5022375"
                Successful   = $false
                Restarted    = $false
                InstanceName = ""
                Installer    = "$TestDrive\MissingUpdate\update.exe"
                ExtractPath  = $null
                Notes        = @()
                ExitCode     = $null
                Log          = $null
            }
            $splatMissingUpdate = @{
                ComputerName = $env:COMPUTERNAME
                Action       = $missingUpdateAction
                ExtractPath  = $TestDrive
            }
            $updateRunspace = [runspacefactory]::CreateRunspace()
            $updateRunspace.Open()
            $importShell = [powershell]::Create()
            $importShell.Runspace = $updateRunspace
            $manifestPath = Join-Path -Path (Get-Module -Name $ModuleName | Select-Object -First 1).ModuleBase -ChildPath "$ModuleName.psd1"
            $null = $importShell.AddCommand("Import-Module").AddParameter("Name", $manifestPath).Invoke()
            $importShell.Dispose()

            $updateShell = [powershell]::Create()
            $updateShell.Runspace = $updateRunspace
            $missingUpdateResult = $updateShell.AddCommand("Invoke-DbaAdvancedUpdate").AddParameters($splatMissingUpdate).Invoke()
            $updateRecords = @($updateShell.Streams.Progress)
            $updateShell.Dispose()
            $updateRunspace.Dispose()
        }

        It "Reports the update as failed" {
            $missingUpdateResult.Successful | Should -Be $false
            $missingUpdateResult.Notes | Should -Match "Extraction failed"
        }

        It "Completes its progress bar" {
            # An Id stays on screen when its last record is not a completed one. Windows PowerShell completes its
            # own bar for loading modules with Id 0 as well, so a completed record somewhere is not enough.
            $openIds = $updateRecords | Group-Object -Property ActivityId | Where-Object { @($PSItem.Group)[-1].RecordType -ne "Completed" } | Select-Object -ExpandProperty Name
            $updateRecords | Where-Object Activity -like "Updating SQL Server components*" | Should -Not -BeNullOrEmpty
            $openIds | Should -BeNullOrEmpty
        }
    }
}
