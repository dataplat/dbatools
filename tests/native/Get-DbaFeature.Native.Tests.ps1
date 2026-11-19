#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: sql-login N/A -- the pinned command has no SqlCredential and opens no SQL connection; Credential is a Windows credential for PowerShell remoting.
# NativeChecklist: azure-sqldb N/A -- the command runs SQL Server setup's discovery report on a Windows host; Azure SQL Database is a managed service with no host operating system, setup.exe or file system to reach. https://learn.microsoft.com/azure/azure-sql/database/sql-database-paas-overview
# NativeChecklist: whatif-confirm N/A -- the pinned command does not declare SupportsShouldProcess, so it has no -WhatIf or -Confirm.
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaFeature",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Get-DbaFeature" -Tag IntegrationTests {
    BeforeAll {
        $featureInstance = New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList $TestConfig.InstanceSingle
        $featureComputer = $featureInstance.ComputerName
        $featureInstanceName = $featureInstance.InstanceName
        $featureMissing = "nf" + [guid]::NewGuid().ToString("N").Substring(0, 12)
        $featureProperties = "ComputerName,Product,Instance,InstanceID,Feature,Language,Edition,Version,Clustered,Configured"
        $featureSession = New-PSSession -ComputerName $featureComputer -ErrorAction Stop

        # Independent reads on the host: the instance id from the registry, the setup.exe the discovery runs and
        # the report folders that exist before this file runs (the AfterAll removes only the ones it added).
        $featureHost = Invoke-Command -Session $featureSession -ArgumentList $featureInstanceName -ErrorAction Stop -ScriptBlock {
            param($instanceName)
            $map = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL" -ErrorAction Stop
            $instanceId = $map.$instanceName
            if (-not $instanceId) { throw "No instance id for $instanceName" }
            $setupVersion = (Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\Setup" -ErrorAction Stop).Version
            $setup = Get-ChildItem -Recurse -Include setup.exe -Path "$([System.Environment]::GetFolderPath("ProgramFiles"))\Microsoft SQL Server" -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match 'Setup Bootstrap\\SQL' -or $_.FullName -match 'Bootstrap\\Release\\Setup.exe' -or $_.FullName -match 'Bootstrap\\Setup.exe' } |
                Sort-Object FullName -Descending | Select-Object -First 1
            if (-not $setup) { throw "No setup.exe on $env:COMPUTERNAME" }
            $logRoot = Join-Path (Split-Path (Split-Path $setup.FullName)) "Log"
            $before = @(Get-ChildItem -LiteralPath $logRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object Name)
            [pscustomobject]@{
                InstanceId   = $instanceId
                VersionMajor = ($setupVersion -split '\.')[0]
                LogRoot      = $logRoot
                Before       = $before
                ComputerName = $env:COMPUTERNAME
            }
        }
    }

    AfterAll {
        if ($featureSession) {
            try {
                if ($featureHost) {
                    # Each discovery run leaves a timestamped folder under Setup Bootstrap\Log. Remove the ones this
                    # file's runs added; a folder is left only while a setup process may still be writing it.
                    Invoke-Command -Session $featureSession -ArgumentList $featureHost.LogRoot, $featureHost.Before -ErrorAction Stop -ScriptBlock {
                        param($logRoot, $before)
                        $running = @(Get-Process -Name setup, setup100, ScenarioEngine, LandingPage -ErrorAction SilentlyContinue)
                        if ($running.Count -gt 0) {
                            Write-Warning "A setup process is running on $env:COMPUTERNAME; discovery folders under $logRoot are left for it."
                            return
                        }
                        foreach ($folder in @(Get-ChildItem -LiteralPath $logRoot -Directory -ErrorAction SilentlyContinue)) {
                            if ($folder.Name -in $before) { continue }
                            if (-not (Test-Path -LiteralPath (Join-Path $folder.FullName "SqlDiscoveryReport.xml"))) { continue }
                            Remove-Item -LiteralPath $folder.FullName -Recurse -Force -ErrorAction Stop
                        }
                    }
                }
            } finally {
                Remove-PSSession -Session $featureSession
            }
        }
    }

    It "returns the discovery rows of each computer and goes on past one that fails" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
        $featureWarnings = @()
        $featureRows = @(@($featureComputer, $featureMissing, $featureComputer) | Get-DbaFeature -EnableException:$false -WarningAction SilentlyContinue -WarningVariable featureWarnings)

        $featureWarnings.Count | Should -Be 1
        "$($featureWarnings[0])" | Should -Match '\[Get-DbaFeature\] Failure \| \S'

        $featureRows.Count | Should -BeGreaterThan 1
        ($featureRows.Count % 2) | Should -Be 0
        foreach ($row in $featureRows) {
            $row | Should -BeOfType [System.Management.Automation.PSCustomObject]
            $row.ComputerName | Should -BeOfType [Dataplat.Dbatools.Parameter.DbaInstanceParameter]
            "$($row.ComputerName)" | Should -BeExactly $featureComputer
            ($row.PSObject.Properties.Name -join ",") | Should -BeExactly $featureProperties
        }

        # Both runs read the same report, row for row.
        $half = $featureRows.Count / 2
        $first = @($featureRows[0..($half - 1)] | ForEach-Object { "$($_.Instance)|$($_.InstanceID)|$($_.Feature)|$($_.Version)" })
        $second = @($featureRows[$half..($featureRows.Count - 1)] | ForEach-Object { "$($_.Instance)|$($_.InstanceID)|$($_.Feature)|$($_.Version)" })
        ($second -join "`n") | Should -BeExactly ($first -join "`n")

        # The claimed instance is in the report as the registry describes it.
        $engine = @($featureRows[0..($half - 1)] | Where-Object { $_.Instance -eq $featureInstanceName -and $_.Feature -eq "Database Engine Services" })
        $engine.Count | Should -Be 1
        $engine[0].InstanceID | Should -BeExactly $featureHost.InstanceId
        ($engine[0].Version -split '\.')[0] | Should -BeExactly $featureHost.VersionMajor
        $engine[0].Product | Should -Not -BeNullOrEmpty
        $engine[0].Edition | Should -Not -BeNullOrEmpty
    }

    It "warns and goes on for a computer it cannot reach, in a plain call and inside a caller's try" -Tag "NativeChecklist:enable-exception" {
        $plainWarnings = @()
        $plainRows = @(Get-DbaFeature -ComputerName $featureMissing -WarningAction SilentlyContinue -WarningVariable plainWarnings)
        $plainRows.Count | Should -Be 0
        $plainWarnings.Count | Should -Be 1
        "$($plainWarnings[0])" | Should -Match '\[Get-DbaFeature\] Failure \| \S'

        $caught = $null
        $tryWarnings = @()
        try {
            $null = Get-DbaFeature -ComputerName $featureMissing -WarningAction SilentlyContinue -WarningVariable tryWarnings
        } catch {
            $caught = $_
        }
        $caught | Should -BeNullOrEmpty
        $tryWarnings.Count | Should -Be 1

        $stopWarnings = @()
        $stopRows = @(Get-DbaFeature -ComputerName $featureMissing -ErrorAction Stop -WarningAction SilentlyContinue -WarningVariable stopWarnings)
        $stopRows.Count | Should -Be 0
        $stopWarnings.Count | Should -Be 1
    }

    It "throws the session failure under -EnableException" -Tag "NativeChecklist:enable-exception" {
        $thrown = $null
        try {
            $null = Get-DbaFeature -ComputerName $featureMissing -EnableException
        } catch {
            $thrown = $_
        }
        $thrown | Should -Not -BeNullOrEmpty
        $exception = $thrown.Exception
        $types = @()
        while ($exception) {
            $types += $exception.GetType().FullName
            $exception = $exception.InnerException
        }
        $types | Should -Contain "System.Management.Automation.Remoting.PSRemotingTransportException"
    }

    It "runs the discovery in this process for the local computer, the default" {
        # Independent read of what the pinned script block would find on this computer.
        $localSetup = Get-ChildItem -Recurse -Include setup.exe -Path "$([System.Environment]::GetFolderPath("ProgramFiles"))\Microsoft SQL Server" -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match 'Setup Bootstrap\\SQL' -or $_.FullName -match 'Bootstrap\\Release\\Setup.exe' -or $_.FullName -match 'Bootstrap\\Setup.exe' } |
            Select-Object -First 1
        $localOutput = @(Get-DbaFeature -Verbose 4>&1)
        $localRows = @($localOutput | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
        $localVerbose = @($localOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | Where-Object { $_.Message -like "*No features found on $env:COMPUTERNAME" })
        if ($localSetup) {
            $localRows.Count | Should -BeGreaterThan 0
            "$($localRows[0].ComputerName)" | Should -BeExactly $env:COMPUTERNAME
            $localVerbose.Count | Should -Be 0
        } else {
            $localRows.Count | Should -Be 0
            $localVerbose.Count | Should -Be 1
        }
    }

    It "runs the discovery in the session's own process on a SQL Server host" {
        # The command on the claimed host itself, where the computer is local: the module goes to a private folder
        # there and is removed again on every path.
        $localRoot = "C:\native\feature-local-" + [guid]::NewGuid().ToString("N")
        $localPayload = $localRoot + "\payload"
        $localSession = $null
        try {
            $null = Invoke-Command -Session $featureSession -ArgumentList $localRoot -ErrorAction Stop -ScriptBlock {
                param($root)
                New-Item -ItemType Directory -Path $root -ErrorAction Stop
            }
            $moduleRoot = (Get-Module -Name $ModuleName -ErrorAction Stop).ModuleBase
            Copy-Item -LiteralPath $moduleRoot -Destination $localPayload -ToSession $featureSession -Recurse -Force -ErrorAction Stop
            $localSession = New-PSSession -ComputerName $featureComputer -ErrorAction Stop
            $localResult = Invoke-Command -Session $localSession -ArgumentList $localPayload, $featureInstanceName -ErrorAction Stop -ScriptBlock {
                param($payload, $instanceName)
                Import-Module ($payload + "\dbatools.psd1") -Force -ErrorAction Stop
                $rows = @(Get-DbaFeature -EnableException)
                [pscustomobject]@{
                    Count        = $rows.Count
                    Computers    = @($rows | ForEach-Object { "$($_.ComputerName)" } | Select-Object -Unique)
                    ComputerType = if ($rows) { $rows[0].ComputerName.GetType().FullName } else { $null }
                    Engine       = @($rows | Where-Object { $_.Instance -eq $instanceName -and $_.Feature -eq "Database Engine Services" } | ForEach-Object { "$($_.InstanceID)|$($_.Version)" })
                }
            }
            $localResult.Count | Should -BeGreaterThan 0
            @($localResult.Computers) | Should -Be @($featureHost.ComputerName)
            $localResult.ComputerType | Should -BeExactly "Dataplat.Dbatools.Parameter.DbaInstanceParameter"
            @($localResult.Engine).Count | Should -Be 1
            ($localResult.Engine[0] -split '\|')[0] | Should -BeExactly $featureHost.InstanceId
            ((($localResult.Engine[0] -split '\|')[1]) -split '\.')[0] | Should -BeExactly $featureHost.VersionMajor
        } finally {
            if ($localSession) { Remove-PSSession -Session $localSession }
            # The closed session's host process can hold the module's DLLs for a moment after it ends.
            Invoke-Command -Session $featureSession -ArgumentList $localRoot -ErrorAction Stop -ScriptBlock {
                param($root)
                $attempt = 0
                while (Test-Path -LiteralPath $root) {
                    $attempt++
                    try {
                        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
                    } catch {
                        if ($attempt -ge 30) { throw }
                        Start-Sleep -Seconds 2
                    }
                }
            }
        }
    }
}
