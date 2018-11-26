$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

$exeDir = "C:\Temp\dbatools_$CommandName"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Prevent the functions from executing dangerous stuff and getting right responses where needed
        Mock -CommandName Invoke-Program -MockWith { $null } -ModuleName dbatools
        Mock -CommandName Test-PendingReboot -MockWith { $false } -ModuleName dbatools
        Mock -CommandName Restart-Computer -MockWith { $null } -ModuleName dbatools
        Mock -CommandName Register-RemoteSessionConfiguration -ModuleName dbatools -MockWith {
            [pscustomobject]@{ 'Name' = 'dbatoolsInstallSqlServerUpdate' ; Successful = $true ; Status = 'Dummy' }
        }
        Mock -CommandName Unregister-RemoteSessionConfiguration -ModuleName dbatools -MockWith {
            [pscustomobject]@{ 'Name' = 'dbatoolsInstallSqlServerUpdate' ; Successful = $true ; Status = 'Dummy' }
        }
    }
    Context "Validate parameters" {
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\$CommandName).Parameters.Keys
        $knownParameters = 'ComputerName', 'Credential', 'SqlServerVersion', 'MajorVersion', 'Type', 'Latest', 'RepositoryPath', 'Restart', 'EnableException','Kb'
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
            #this is our 'currently installed' versions
            Mock -CommandName Get-SqlServerVersion -ModuleName dbatools -MockWith {
                @(
                    Get-DbaBuildReference -SqlServerVersion 2016 -ServicePack 1 -CumulativeUpdate 3
                    Get-DbaBuildReference -SqlServerVersion 2008 -ServicePack 2 -CumulativeUpdate 3
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
        It "Should mock-upgrade SQL2008 to SP3" {
            $result = Update-DbaInstance -ComputerName $script:instance1 -SqlServerVersion 2008SP3 -RepositoryPath $exeDir -Restart -EnableException -Confirm:$false
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
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'
        }
        It "Should mock-upgrade SQL2008 to SP2CU5" {
            $result = Update-DbaInstance -ComputerName $script:instance1 -SqlServerVersion 2008SP2CU5 -RepositoryPath $exeDir -Restart -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Get-SqlServerVersion -Exactly 2 -Scope It -ModuleName dbatools
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
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'
        }
        It "Should mock-upgrade SQL2016 to CU5" {
            $result = Update-DbaInstance -ComputerName $script:instance1 -SqlServerVersion 2016CU5 -RepositoryPath $exeDir -Restart -EnableException -Confirm:$false
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
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'
        }
        It "Should mock-upgrade both versions to different SPs" {
            $results = Update-DbaInstance -ComputerName $script:instance1 -SqlServerVersion 2016SP1CU5, SQL2008SP3CU7 -RepositoryPath $exeDir -Restart -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Get-SqlServerVersion -Exactly 4 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -Exactly 6 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 3 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Register-RemoteSessionConfiguration -Exactly 0 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Unregister-RemoteSessionConfiguration -Exactly 1 -Scope It -ModuleName dbatools

            ($results | Measure-Object).Count | Should -Be 3

            #2016SP1CU5
            $result = $results | Select-Object -First 1
            $result.MajorVersion | Should -Be 2016
            $result.TargetLevel | Should -Be SP1CU5
            $result.KB | Should -Be 4040714
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2016-KB4040714-x64.exe')
            $result.Message | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'

            #2008SP3
            $result = $results | Select-Object -First 1 -Skip 1
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP3
            $result.KB | Should -Be 2546951
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2008SP3-KB2546951-x64-ENU.exe')
            $result.Message | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'

            #2008SP3CU7
            $result = $results | Select-Object -First 1 -Skip 2
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP3CU7
            $result.KB | Should -Be 2738350
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2008-KB2738350-x64-ENU.exe')
            $result.Message | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'
        }
        It "Should mock-upgrade SQL2008 to SP3CU5 without restart" {
            $result = Update-DbaInstance -ComputerName $script:instance1 -SqlServerVersion 2008SP3CU5 -RepositoryPath $exeDir -EnableException -WarningVariable warningVar -Confirm:$false 3>$null
            Assert-MockCalled -CommandName Get-SqlServerVersion -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 0 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Register-RemoteSessionConfiguration -Exactly 0 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Unregister-RemoteSessionConfiguration -Exactly 1 -Scope It -ModuleName dbatools

            $warningVar | Should -BeLike '*restart * to complete the installation of SQL2008SP3*'
            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP3
            $result.KB | Should -Be 2546951
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $false
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2008SP3-KB2546951-x64-ENU.exe')
            $result.Message | Should -BeLike "Restart is required for computer * to finish the installation of SQL2008SP3"
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'
        }
    }
    Context "Validate upgrades to a latest version" {
        BeforeAll {
            #this is our 'currently installed' versions
            Mock -CommandName Get-SqlServerVersion -ModuleName dbatools -MockWith {
                @(
                    Get-DbaBuildReference -SqlServerVersion 2012 -ServicePack 2
                    Get-DbaBuildReference -SqlServerVersion 2008 -ServicePack 3 -CumulativeUpdate 3
                )
            }
            if (-Not(Test-Path $exeDir)) {
                $null = New-Item -ItemType Directory -Path $exeDir
            }
            #Create dummy files for specific patch versions
            $kbs = @(
                'SQLServer2008SP4-KB2979596-x64-ENU.exe'
                'SQLServer2012-KB4018073-x64-ENU.exe'
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
        It "Should mock-upgrade SQL2008 to latest SP" {
            $result = Update-DbaInstance -ComputerName $script:instance1 -MajorVersion 2008 -Latest -Type ServicePack -RepositoryPath $exeDir -Restart -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Get-SqlServerVersion -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Register-RemoteSessionConfiguration -Exactly 0 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Unregister-RemoteSessionConfiguration -Exactly 1 -Scope It -ModuleName dbatools

            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP4
            $result.KB | Should -Be 2979596
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2008SP4-KB2979596-x64-ENU.exe')
            $result.Message | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'
        }
        It "Should mock-upgrade both versions to latest SPs" {
            $results = Update-DbaInstance -ComputerName $script:instance1 -Type ServicePack -Latest -RepositoryPath $exeDir -Restart -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Get-SqlServerVersion -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -Exactly 4 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Register-RemoteSessionConfiguration -Exactly 0 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Unregister-RemoteSessionConfiguration -Exactly 1 -Scope It -ModuleName dbatools

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
            $result.Message | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'

            #2012SP4
            $result = $results | Where-Object MajorVersion -eq 2012
            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2012
            $result.TargetLevel | Should -Be SP4
            $result.KB | Should -Be 4018073
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2012-KB4018073-x64-ENU.exe')
            $result.Message | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'
        }
    }
    Context "Validate upgrades to a specific KB" {
        BeforeAll {
            #this is our 'currently installed' versions
            Mock -CommandName Get-SqlServerVersion -ModuleName dbatools -MockWith {
                @(
                    Get-DbaBuildReference -SqlServerVersion 2016 -ServicePack 1 -CumulativeUpdate 3
                    Get-DbaBuildReference -SqlServerVersion 2008 -ServicePack 2 -CumulativeUpdate 3
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
            $result = Update-DbaInstance -ComputerName $script:instance1 -Kb KB2546951 -RepositoryPath $exeDir -Restart -EnableException -Confirm:$false
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
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'
        }
        It "Should mock-upgrade SQL2008 to SP2CU5 (KB979450 + KB2555408) " {
            $result = Update-DbaInstance -ComputerName $script:instance1 -Kb 979450, 2555408 -RepositoryPath $exeDir -Restart -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Get-SqlServerVersion -Exactly 2 -Scope It -ModuleName dbatools
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
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'
        }
        It "Should mock-upgrade both versions to different KBs" {
            $results = Update-DbaInstance -ComputerName $script:instance1 -Kb 3182545, 4040714, KB2546951, KB2738350 -RepositoryPath $exeDir -Restart -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Get-SqlServerVersion -Exactly 4 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -Exactly 6 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 3 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Register-RemoteSessionConfiguration -Exactly 0 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Unregister-RemoteSessionConfiguration -Exactly 1 -Scope It -ModuleName dbatools

            ($results | Measure-Object).Count | Should -Be 3

            #2016SP1CU5
            $result = $results | Select-Object -First 1
            $result.MajorVersion | Should -Be 2016
            $result.TargetLevel | Should -Be SP1CU5
            $result.KB | Should -Be 4040714
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2016-KB4040714-x64.exe')
            $result.Message | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'

            #2008SP3
            $result = $results | Select-Object -First 1 -Skip 1
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP3
            $result.KB | Should -Be 2546951
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2008SP3-KB2546951-x64-ENU.exe')
            $result.Message | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'

            #2008SP3CU7
            $result = $results | Select-Object -First 1 -Skip 2
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP3CU7
            $result.KB | Should -Be 2738350
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2008-KB2738350-x64-ENU.exe')
            $result.Message | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'
        }
    }
    Context "Negative tests" {
        BeforeAll {
            #this is our 'currently installed' versions
            Mock -CommandName Get-SqlServerVersion -ModuleName dbatools -MockWith {
                @(
                    Get-DbaBuildReference -SqlServerVersion 2008 -ServicePack 2 -CumulativeUpdate 3
                )
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
            { Update-DbaInstance -ComputerName $script:instance1 -SqlServerVersion 2008SP3CU7 -EnableException } | Should throw 'Reboot the computer before proceeding'
            #revert default mock
            Mock -CommandName Test-PendingReboot -MockWith { $false } -ModuleName dbatools
        }
        It "fails when SqlServerVersion string is incorrect" {
            { Update-DbaInstance -ComputerName $script:instance1 -SqlServerVersion '' -EnableException } | Should throw 'Cannot validate argument on parameter ''SqlServerVersion'''
            { Update-DbaInstance -ComputerName $script:instance1 -SqlServerVersion $null -EnableException } | Should throw 'Cannot validate argument on parameter ''SqlServerVersion'''
            { Update-DbaInstance -ComputerName $script:instance1 -SqlServerVersion SQL2008 -EnableException } | Should throw 'Either SP or CU should be specified'
            { Update-DbaInstance -ComputerName $script:instance1 -SqlServerVersion SQL2008-SP3 -EnableException } | Should throw 'is an incorrect SqlServerVersion value'
            { Update-DbaInstance -ComputerName $script:instance1 -SqlServerVersion SP2CU -EnableException } | Should throw 'is an incorrect SqlServerVersion value'
            { Update-DbaInstance -ComputerName $script:instance1 -SqlServerVersion SPCU2 -EnableException } | Should throw 'is an incorrect SqlServerVersion value'
            { Update-DbaInstance -ComputerName $script:instance1 -SqlServerVersion SQLSP2CU2 -EnableException } | Should throw 'is an incorrect SqlServerVersion value'
        }
        It "fails when MajorVersion string is incorrect" {
            { Update-DbaInstance -ComputerName $script:instance1 -MajorVersion 08 -Latest -EnableException } | Should throw 'is an incorrect MajorVersion value'
            { Update-DbaInstance -ComputerName $script:instance1 -MajorVersion 2008SP3 -Latest -EnableException } | Should throw 'is an incorrect MajorVersion value'
        }
        It "fails when KB is missing in the folder" {
            { Update-DbaInstance -ComputerName $script:instance1 -Latest -RepositoryPath $exeDir -EnableException } | Should throw 'Could not find installer for the SQL2008 update KB'
            { Update-DbaInstance -ComputerName $script:instance1 -SqlServerVersion 2008SP3CU7 -RepositoryPath $exeDir -EnableException } | Should throw 'Could not find installer for the SQL2008 update KB'
        }
        It "fails when SP level is lower than required" {
            { Update-DbaInstance -ComputerName $script:instance1 -Latest -Type CumulativeUpdate -EnableException } | Should throw 'Current SP version SQL2008SP2 is not the latest available'
        }
        It "fails when repository is not available" {
            { Update-DbaInstance -ComputerName $script:instance1 -SqlServerVersion 2008SP3CU7 -RepositoryPath .\NonExistingFolder -EnableException } | Should throw 'Cannot find path'
            { Update-DbaInstance -ComputerName $script:instance1 -SqlServerVersion 2008SP3CU7 -EnableException } | Should throw 'Path to SQL Server updates folder is not set'
        }
    }
}