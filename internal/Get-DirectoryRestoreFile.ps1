function Get-DirectoryRestoreFile {
    <#
.SYNOPSIS
Internal Function to get SQL Server backfiles from a specified folder

.DESCRIPTION
Takes path, checks for validity. Scans for usual backup file 
#>
    [CmdletBinding()]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Path,
        [switch]$recurse,
        [switch]$silent
    )
       
    Write-Message -Level Verbose -Message "Starting"
    Write-Message -Level Verbose -Message "Checking Path"
    if ((Test-Path $Path) -ne $true) {
        Write-Message -Level Verbose -Message "$Path is not reachable" -WarningAction stop
    }
    #Path needs to end \* to use includes, which is faster than Where-Object
    $PathCheckArray = $path.ToCharArray()
    if ($PathCheckArray[-2] -eq '\' -and $PathCheckArray[-1] -eq '*') {
        #We're good    
    }
    elseif ($PathCheckArray[-2] -ne '\' -and $PathCheckArray[-1] -eq '*') {
        $Path = ($PathCheckArray[0..(($PathCheckArray.length) - 2)] -join ('')) + "\*"
    }
    elseif ($PathCheckArray[-2] -eq '\' -and $PathCheckArray[-1] -ne '*') {
        #Append a * to the end
        $Path = "$Path*"
    }
    elseif ($PathCheckArray[-2] -ne '\' -and $PathCheckArray[-1] -ne '*') {
        #Append a \* to the end
        $Path = "$Path\*"
    }
    Write-Message -Level Verbose -Message "Scanning $path"
    $Results = Get-ChildItem -path $Path -Recurse:$recurse | Where-Object {$_.PsIsContainer -eq $false}
    return $Results
}
