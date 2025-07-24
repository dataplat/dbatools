$ErrorActionPreference = 'Stop'

$stopOnFailure = $false

$start = Get-Date

$repoBase = 'C:\GitHub\dbatools'

Import-Module -Name "$repoBase\dbatools.psm1" -Force
$null = Set-DbatoolsInsecureConnection

Copy-Item -Path "$repoBase\tests\Environment\constants.local.ps1" -Destination "$repoBase\tests\"
$TestConfig = Get-TestConfig

$tests = Get-ChildItem -Path "$repoBase\tests\*-Dba*.Tests.ps1"

$skipTests = @(
    'Add-DbaAgReplica.Tests.ps1'       # Needs an seconds Hadr-instance
    'Invoke-DbaDbMirroring.Tests.ps1'  # "the partner server name must be distinct"
    'Watch-DbaDbLogin.Tests.ps1'       # Command does not work
    'Get-DbaWindowsLog.Tests.ps1'      # Sometimes failes (gets no data), sometimes takes forever
    'Get-DbaPageFileSetting.Tests.ps1' # Classes Win32_PageFile and Win32_PageFileSetting do not return any information
    'New-DbaSsisCatalog.Tests.ps1'     # needs an SSIS server
    'Get-DbaClientProtocol.Tests.ps1'  # No ComputerManagement Namespace on CLIENT.dom.local
    #'Copy-DbaDbAssembly.Tests.ps1'     # Sometimes: Error occurred in Describe block: Must declare the scalar variable "@assemblyName".
    #'New-DbaDbMailAccount.Tests.ps1'   # Sometimes: Context Gets no DbMail when using -ExcludeAccount     [-] Gets no results 106ms      Expected $null, but got [dbatoolsci_test_672856400].      96:             $results | Should Be $null        at <ScriptBlock>, C:\GitHub\dbatools\tests\New-DbaDbMailAccount.Tests.ps1: line 96
    'New-DbaLogin.Tests.ps1'           # fixed in other pr
    'Copy-DbaDatabase.Tests.ps1'       # fixed in other pr
    'Test-DbaDeprecatedFeature.Tests.ps1'  # The command will be deleted
)
$tests = $tests | Where-Object Name -notin $skipTests

if ($PSVersionTable.PSVersion.Major -gt 5) {
    $skipTests = @(
        'Add-DbaComputerCertificate.Tests.ps1'    # does not work on pwsh because of X509Certificate2
        'Backup-DbaComputerCertificate.Tests.ps1' # does not work on pwsh because of X509Certificate2
        'Enable-DbaFilestream.Tests.ps1'          # does not work on pwsh because of WMI-Object not haveing method EnableFilestream
        'Invoke-DbaQuery.Tests.ps1'               # does not work on pwsh because "DataReader.GetFieldType(0) returned null." with geometry
    )
}
$tests = $tests | Where-Object Name -notin $skipTests


# Pester 5
##########

$tests5 = $tests | Where-Object { (Get-Content -Path $_.FullName)[0] -match 'Requires.*Pester.*5' }

$resultsFileName = "$repoBase\tests\Environment\logs\_results_5_$([datetime]::Now.ToString('yyyMMdd_HHmmss')).txt"
$failedFileName = "$repoBase\tests\Environment\logs\_failed_5_$([datetime]::Now.ToString('yyyMMdd_HHmmss')).txt"

$pester5Config = New-PesterConfiguration
$pester5config.Run.PassThru = $true
$pester5config.Output.Verbosity = 'Detailed'  # 'None', 'Normal', 'Detailed' or 'Diagnostic'

$progressParameter = @{ Id = Get-Random ; Activity = 'Running tests' }
$progressTotal = $tests5.Count
$progressCompleted = 0
$progressStart = Get-Date
foreach ($test in $tests5) {
    # $test = $tests5[0]

    $progressParameter.Status = "$progressCompleted of $progressTotal tests completed"
    $progressParameter.CurrentOperation = "processing $($test.Name)"
    $progressParameter.PercentComplete = $progressCompleted * 100 / $progressTotal
    if ($progressParameter.PercentComplete -gt 0) {
        $progressParameter.SecondsRemaining = ((Get-Date) - $progressStart).TotalSeconds / $progressParameter.PercentComplete * (100 - $progressParameter.PercentComplete)
    }
    Write-Progress @progressParameter

    Write-Host "`n======================================================================================`n"

    $pester5Config.Run.Path = $test.FullName
    $result = Invoke-Pester -Configuration $pester5config

    $resultInfo = [ordered]@{
        TestFileName    = $test.Name
        Result          = $result.Result
        DurationSeconds = $result.Duration.TotalSeconds
        TotalCount      = $result.TotalCount
        PassedCount     = $result.PassedCount
        FailedCount     = $result.FailedCount
        SkippedCount    = $result.SkippedCount
    }
    $resultInfo | ConvertTo-Json -Compress | Add-Content -Path $resultsFileName

    if ($result.FailedCount -gt 0) {
        $test.Name | Add-Content -Path $failedFileName
        if ($stopOnFailure) {
            Write-Warning -Message "Failed after $([int]((Get-Date) - $progressStart).TotalMinutes) minutes and $progressCompleted of $progressTotal tests"
            return
        }
    }

    $result = $null
    [System.GC]::Collect()

    $progressCompleted++
}
Write-Progress @progressParameter -Completed


# Pester 4
##########

Remove-Module -Name Pester -ErrorAction SilentlyContinue
Import-Module -Name Pester -MaximumVersion 4.99

$tests4 = $tests | Where-Object { (Get-Content -Path $_.FullName)[0] -notmatch 'Requires.*Pester.*5' }

$resultsFileName = "$repoBase\tests\Environment\logs\_results_4_$([datetime]::Now.ToString('yyyMMdd_HHmmss')).txt"
$failedFileName = "$repoBase\tests\Environment\logs\_failed_4_$([datetime]::Now.ToString('yyyMMdd_HHmmss')).txt"

$progressParameter = @{ Id = Get-Random ; Activity = 'Running tests' }
$progressTotal = $tests4.Count
$progressCompleted = 0
$progressStart = Get-Date
foreach ($test in $tests4) {
    # $test = $tests4[0]

    $progressParameter.Status = "$progressCompleted of $progressTotal tests completed"
    $progressParameter.CurrentOperation = "processing $($test.Name)"
    $progressParameter.PercentComplete = $progressCompleted * 100 / $progressTotal
    if ($progressParameter.PercentComplete -gt 0) {
        $progressParameter.SecondsRemaining = ((Get-Date) - $progressStart).TotalSeconds / $progressParameter.PercentComplete * (100 - $progressParameter.PercentComplete)
    }
    Write-Progress @progressParameter

    Write-Host "`n======================================================================================`n"

    $result = Invoke-Pester -Script $test.FullName -Show All -PassThru

    $resultInfo = [ordered]@{
        TestFileName    = $test.Name
        Result          = $(if ($result.FailedCount -eq 0) { 'Passed' } else { 'Failed' })
        DurationSeconds = $result.Time.TotalSeconds
        TotalCount      = $result.TotalCount
        PassedCount     = $result.PassedCount
        FailedCount     = $result.FailedCount
        SkippedCount    = $result.SkippedCount
    }
    $resultInfo | ConvertTo-Json -Compress | Add-Content -Path $resultsFileName

    if ($result.FailedCount -gt 0) {
        $test.Name | Add-Content -Path $failedFileName
        if ($stopOnFailure) {
            Write-Warning -Message "Failed after $([int]((Get-Date) - $progressStart).TotalMinutes) minutes and $progressCompleted of $progressTotal tests"
            return
        }
    }

    $result = $null
    [System.GC]::Collect()

    $progressCompleted++
}
Write-Progress @progressParameter -Completed


Write-Warning -Message "Finished after $([int]((Get-Date) - $start).TotalMinutes) minutes and $($tests.Count) tests"



break



# Reporting:

$results = Get-Content -Path C:\GitHub\dbatools\tests\Environment\logs\_results_*.txt | ConvertFrom-Json
$results | Sort-Object DurationSeconds -Descending | Select-Object -First 15 -Property TestFileName, @{ l = 'Seconds' ; e = { [int]$_.DurationSeconds } }


# Run individual Pester 5 tests:

Remove-Module -Name Pester -ErrorAction SilentlyContinue
Import-Module -Name Pester -MinimumVersion 5.0

$pester5Config = New-PesterConfiguration
$pester5config.Output.Verbosity = 'Detailed'  # 'None', 'Normal', 'Detailed' or 'Diagnostic'

$pester5Config.Run.Path = 'C:\GitHub\dbatools\tests\Copy-DbaEndpoint.Tests.ps1'
Invoke-Pester -Configuration $pester5config

Get-DbaEndpoint -SqlInstance client\sqlinstance2 -Type DatabaseMirroring



# Run individual Pester 4 tests:

Remove-Module -Name Pester -ErrorAction SilentlyContinue
Import-Module -Name Pester -MaximumVersion 4.99

Invoke-Pester -Script 'C:\GitHub\dbatools\tests\Watch-DbaXESession.Tests.ps1' -Show All
