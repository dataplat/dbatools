function Get-TestInstanceUsage {
<#
.SYNOPSIS
    Reports which $TestConfig instances each test file uses.

.DESCRIPTION
    tests\pester.groups.ps1 assigns a test file to a CI scenario by autodetecting which
    $TestConfig.Instance* variable the file references, so this is what decides which lane a test
    runs in - and the lanes are not equally available. Only InstanceSingle, InstanceMulti1 and
    InstanceMulti2 exist on GitHub Actions; a test written against InstanceCopy, InstanceHadr or
    InstanceRestart runs on the Azure runners only.

    Use it to see which lane a change lands in before writing the test, or to find every test that
    a given instance would affect.

    Commented out code is ignored, so a reference left behind in a comment does not move a file
    into a scenario it does not belong to.

.PARAMETER Path
    The folder holding the test files. Defaults to the tests folder of this working copy.

.PARAMETER Command
    Only report the test files of these commands. Wildcards are supported. Defaults to all of them.

.EXAMPLE
    Get-TestInstanceUsage

    Reports the instances used by every test file.

.EXAMPLE
    Get-TestInstanceUsage -Command Get-DbaDb*

    Reports the instances used by the test files of every command starting with Get-DbaDb.

.EXAMPLE
    Get-TestInstanceUsage | Group-Object -Property InstanceList -NoElement | Sort-Object -Property Count -Descending

    Shows how many test files use each combination of instances.

.EXAMPLE
    Get-TestInstanceUsage | Where-Object Instances -contains "Hadr"

    Lists every test that needs the availability group instance, which only the Azure runners have.
#>
    [CmdletBinding()]
    param (
        [string]$Path = (Join-Path (Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent) "tests"),
        [string[]]$Command = "*"
    )

    foreach ($commandName in $Command) {
        $testFiles = Get-ChildItem -Path "$Path\$commandName.Tests.ps1" -ErrorAction SilentlyContinue | Sort-Object -Property Name
        if (-not $testFiles) {
            Write-Warning -Message "No test file found for [$commandName]"
            continue
        }

        foreach ($testFile in $testFiles) {
            $content = Get-Content -Path $testFile.FullName
            # This matches the current names ($TestConfig.InstanceSingle, $TestConfig.InstanceMulti1
            # and so on) as well as the legacy $TestConfig.instance1, because both spellings still
            # appear in the autodetection in pester.groups.ps1.
            $instanceNames = foreach ($line in $content) {
                $code = $line -replace "#.*$", ""
                [regex]::Matches($code, "\`$TestConfig\.Instance(\w+)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) |
                    ForEach-Object { $PSItem.Groups[1].Value }
            }
            $instanceNames = @($instanceNames | Sort-Object -Unique)

            [PSCustomObject]@{
                Command      = $testFile.Name -replace "\.Tests\.ps1$", ""
                TestFileName = $testFile.Name
                Instances    = $instanceNames
                # A single string as well, so that the result can be grouped on it directly
                InstanceList = $instanceNames -join " "
            }
        }
    }
}
