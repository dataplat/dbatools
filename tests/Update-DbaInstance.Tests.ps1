$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

$exeDir = "C:\Temp\dbatools_$CommandName"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\$CommandName).Parameters.Keys
        $knownParameters = 'ComputerName', 'Credential', 'SqlServerVersion', 'MajorVersion', 'Type', 'Latest', 'RepositoryPath', 'Restart', 'EnableException'
        $paramCount = $knownParameters.Count
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
    Context "Validate upgrades to a specific version" {
        BeforeAll {
            Mock -CommandName Invoke-Program -MockWith { $null } -ModuleName dbatools
            Mock -CommandName Test-PendingReboot -MockWith { $false } -ModuleName dbatools
            Mock -CommandName Restart-Computer -MockWith { $null } -ModuleName dbatools
            Mock -CommandName Register-RemoteSessionConfiguration -ModuleName dbatools -MockWith {
                [pscustomobject]@{ 'Name' = 'dbatoolsInstallSqlServerUpdate' ; Successful = $true ; Status = 'Dummy' }
            }
            Mock -CommandName Unregister-RemoteSessionConfiguration -ModuleName dbatools -MockWith {
                [pscustomobject]@{ 'Name' = 'dbatoolsInstallSqlServerUpdate' ; Successful = $true ; Status = 'Dummy' }
            }
            Mock -CommandName Get-SqlServerVersion -ModuleName dbatools -MockWith {
                @(
                    Get-DbaBuildReference -SqlServerVersion 2016 -ServicePack 1 -CumulativeUpdate 3
                    Get-DbaBuildReference -SqlServerVersion 2008 -ServicePack 2 -CumulativeUpdate 3
                )
            }
            if (-Not(Test-Path $exeDir)) {
                New-Item -ItemType Directory -Path $exeDir
            }
            New-Item -ItemType File -Path (Join-Path $exeDir 'SQLServer2008SP3-KB2546951-x64-ENU.exe') -Force
            New-Item -ItemType File -Path (Join-Path $exeDir 'SQLServer2008-KB2555408-x64-ENU.exe') -Force
            New-Item -ItemType File -Path (Join-Path $exeDir 'SQLServer2008-KB2738350-x64-ENU.exe') -Force
            New-Item -ItemType File -Path (Join-Path $exeDir 'SQLServer2016-KB4040714-x64.exe') -Force
        }
        AfterAll {
            if (Test-Path $exeDir) {
                Remove-Item $exeDir -Force -Recurse
            }
        }
        It "Should mock-upgrade SQL2008 to SP3" {
            $result = Update-DbaInstance -ComputerName $script:instance1 -SqlServerVersion 2008SP3 -RepositoryPath $exeDir -Restart -enableexception
            Assert-MockCalled -CommandName Get-SqlServerVersion -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Register-RemoteSessionConfiguration -Exactly 0 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Unregister-RemoteSessionConfiguration -Exactly 1 -Scope It -ModuleName dbatools

            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP3
            $result.KB | Should -Be 2546951
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2008SP3-KB2546951-x64-ENU.exe')
            $result.Message | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*temp*_extract*'
        }
        It "Should mock-upgrade SQL2008 to SP2CU5" {
            $result = Update-DbaInstance -ComputerName $script:instance1 -SqlServerVersion 2008SP2CU5 -RepositoryPath $exeDir -Restart -enableexception
            Assert-MockCalled -CommandName Get-SqlServerVersion -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Register-RemoteSessionConfiguration -Exactly 0 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Unregister-RemoteSessionConfiguration -Exactly 1 -Scope It -ModuleName dbatools

            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP2CU5
            $result.KB | Should -Be 2555408
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2008-KB2555408-x64-ENU.exe')
            $result.Message | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*temp*_extract*'
        }
        It "Should mock-upgrade SQL2016 to CU5" {
            $result = Update-DbaInstance -ComputerName $script:instance1 -SqlServerVersion 2016CU5 -RepositoryPath $exeDir -Restart -enableexception
            Assert-MockCalled -CommandName Get-SqlServerVersion -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Register-RemoteSessionConfiguration -Exactly 0 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Unregister-RemoteSessionConfiguration -Exactly 1 -Scope It -ModuleName dbatools

            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2016
            $result.TargetLevel | Should -Be SP1CU5
            $result.KB | Should -Be 4040714
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2016-KB4040714-x64.exe')
            $result.Message | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*temp*_extract*'
        }
        It "Should mock-upgrade both versions to different SPs" {
            $results = Update-DbaInstance -ComputerName $script:instance1 -SqlServerVersion 2016SP1CU5, SQL2008SP3CU7 -RepositoryPath $exeDir -Restart -enableexception
            Assert-MockCalled -CommandName Get-SqlServerVersion -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -Exactly 4 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Register-RemoteSessionConfiguration -Exactly 0 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Unregister-RemoteSessionConfiguration -Exactly 1 -Scope It -ModuleName dbatools

            ($results | Measure-Object).Count | Should -Be 2

            #2016
            $result = $results | Select-Object -First 1
            $result.MajorVersion | Should -Be 2016
            $result.TargetLevel | Should -Be SP1CU5
            $result.KB | Should -Be 4040714
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2016-KB4040714-x64.exe')
            $result.Message | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*temp*_extract*'

            #2008
            $result = $results | Select-Object -First 1 -Skip 1
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP3CU7
            $result.KB | Should -Be 2738350
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2008SP3-KB2738350-x64-ENU.exe')
            $result.Message | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*temp*_extract*'

        }
    }
}