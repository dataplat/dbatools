function Get-DirectoryRestoreFile {
    <#
.SYNOPSIS
Internal Function to get SQL Server backfiles from a specified folder

.DESCRIPTION
Takes path, checks for validity. Scans for usual backup file
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [string]$Path,
        [switch]$Recurse,
        [switch]$EnableException
    )

    Write-Message -Level Verbose -Message "Starting"
    Write-Message -Level Verbose -Message "Checking Path"
    if ((Test-Path $Path) -ne $true) {
        Stop-Function -Message "$Path is not reachable"
        return
    }
    #Path needs to end \* to use includes, which is faster than Where-Object
    $PathCheckArray = $path.ToCharArray()
    if ($PathCheckArray[-2] -eq '\' -and $PathCheckArray[-1] -eq '*') {
        #We're good
    } elseif ($PathCheckArray[-2] -ne '\' -and $PathCheckArray[-1] -eq '*') {
        $Path = ($PathCheckArray[0..(($PathCheckArray.length) - 2)] -join ('')) + "\*"
    } elseif ($PathCheckArray[-2] -eq '\' -and $PathCheckArray[-1] -ne '*') {
        #Append a * to the end
        $Path = "$Path*"
    } elseif ($PathCheckArray[-2] -ne '\' -and $PathCheckArray[-1] -ne '*') {
        #Append a \* to the end
        $Path = "$Path\*"
    }
    Write-Message -Level Verbose -Message "Scanning $path"
    $Results = Get-ChildItem -path $Path -Recurse:$Recurse | Where-Object { $_.PsIsContainer -eq $false }
    return $Results
}