# This script will invoke pester tests
# It should invoke on PowerShell v2 and later
# We serialize XML results and pull them in appveyor.yml

#If Finalize is specified, we collect XML output, upload tests, and indicate build errors
param([switch]$Finalize)

#Initialize some variables, move to the project root
$PSVersion = $PSVersionTable.PSVersion.Major
$TestFile = "TestResultsPS$PSVersion.xml"
$ProjectRoot = $ENV:APPVEYOR_BUILD_FOLDER
$ModuleBase = $ProjectRoot
Set-Location $ProjectRoot

Import-Module "$ProjectRoot\dbatools.psm1" -DisableNameChecking
$ScriptAnalyzerRules = Get-ScriptAnalyzerRule

#Run a test with the current version of PowerShell
#Make things faster by removing most output
if(-not $Finalize)
{
    "`n`tSTATUS: Testing with PowerShell $PSVersion`n"
	
    Import-Module Pester
	Set-Variable ProgressPreference -Value SilentlyContinue
    Invoke-Pester -Quiet -Path "$ProjectRoot\Tests" -OutputFormat NUnitXml -OutputFile "$ProjectRoot\$TestFile" -PassThru |
    Export-Clixml -Path "$ProjectRoot\PesterResults$PSVersion.xml"
}

#If finalize is specified, check for failures and 
else
{
    #Show status...
    $AllFiles = Get-ChildItem -Path $ProjectRoot\*Results*.xml | Select-Object -ExpandProperty FullName
    "`n`tSTATUS: Finalizing results`n"
    "COLLATING FILES:`n$($AllFiles | Out-String)"

    #Upload results for test page
    Get-ChildItem -Path "$ProjectRoot\TestResultsPS*.xml" | Foreach-Object {

        $Address = "https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)"
        $Source = $_.FullName

        "UPLOADING FILES: $Address $Source"

        (New-Object 'System.Net.WebClient').UploadFile( $Address, $Source )
    }

    #What failed?
    $Results = @( Get-ChildItem -Path "$ProjectRoot\PesterResults*.xml" | Import-Clixml )
    
    $FailedCount = $Results |
        Select-Object -ExpandProperty FailedCount |
        Measure-Object -Sum |
        Select-Object -ExpandProperty Sum

    if ($FailedCount -gt 0) {

        $FailedItems = $Results |
            Select-Object -ExpandProperty TestResult |
            Where-Object {$_.Passed -notlike $True}

        "FAILED TESTS SUMMARY:`n"
        $FailedItems | ForEach-Object {
            $Test = $_
            [pscustomobject]@{
                Describe = $Test.Describe
                Context = $Test.Context
                Name = "It $($Test.Name)"
                Result = $Test.Result
            }
        } |
            Sort-Object Describe, Context, Name, Result |
            Format-List

        throw "$FailedCount tests failed."
    }
}
