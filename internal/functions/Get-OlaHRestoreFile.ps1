function Get-OlaHRestoreFile {
    <#
.SYNOPSIS
Internal Function to get SQL Server backfiles from a specified folder that's formatted according to Ola Hallengreen's scripts.

.DESCRIPTION
Takes path, checks for validity. Scans for usual backup file
#>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Path,
        [switch]$IgnoreLogBackup,
        [switch][Alias('Silent')]$EnableException
    )

    Write-Message -Level Verbose -Message "Starting"
    Write-Message -Level Verbose -Message "Checking Path"

    if ((Test-Path $Path) -ne $true) {
        Write-Message -Level Warning -Message "$Path is not valid"
        return
    }

    #There should be at least FULL folder, DIFF and LOG are nice as well
    Write-Message -Level Verbose -Message "Checking we have a FULL folder"

    if (Test-Path -Path $Path\FULL) {
        Write-Message -Level Verbose -Message "We have a FULL folder, scanning"
        $Results = Get-ChildItem -Path $Path\FULL -Filter *.bak
        $results = @($results)
    }
    else {
        if ($MaintenanceSolutionBackup) {
            Write-Message -Level Warning -Message "Don't have a FULL folder"
        }
        else {
            Write-Message -Level Warning -Message "No valid backup found - even tried MaintenanceSolution structure"
        }
        return
    }
    if (!$IgnoreLogBackup) {
        if (Test-Path -Path $Path\Log) {
            Write-Message -Level Verbose -Message "We have a LOG folder, scanning"
            $Results += Get-ChildItem -Path $Path\LOG -filter *.trn
        }
    }
    else {
        Write-Message -Level Verbose -Message "Skipping logs as instructed"
    }
    if (Test-Path -Path $Path\Diff) {
        Write-Message -Level Verbose -Message "$FunctionName - We have a DIFF folder, scanning"
        $Results += Get-ChildItem -Path $Path\DIFF -filter *.bak
    }
    return $Results
}
