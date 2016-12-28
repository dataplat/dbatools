function Get-DirectoryRestoreFile
{
<#
.SYNOPSIS
Internal Function to get SQL Server backfiles from a specified folder

.DESCRIPTION
Takes path, checks for validity. Scans for usual backup file 
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[string]$Path
	)
       
        Write-Verbose "$FunctionName - Starting"
        Write-Verbose "$FunctionName - Checking Path"
        if ((Test-Path $Path) -ne $true){
            break
        }
        #Path needs to end \* to use includes, which is faster than Where-Object
        $PathCheckArray = $path.ToCharArray()
        if ($PathCheckArray[-2] -eq '\' -and $PathCheckArray[-1] -eq '*'){
            #We're good    
        } elseif ($PathCheckArray[-2] -ne '\' -and $PathCheckArray[-1] -eq '*') {
            #We have \\some\path*, insert a \
            write-verbose "here"
            $Path = ($PathCheckArray[0..(($PathCheckArray.length)-2)] -join (''))+"\*"
        } elseif ($PathCheckArray[-2] -eq '\' -and $PathCheckArray[-1] -ne '*') {
            #Append a * to the end
            $Path = "$Path*"
        } elseif ($PathCheckArray[-2] -ne '\' -and $PathCheckArray[-1] -ne '*') {
            #Append a \* to the end
            $Path = "$Path\*"
        }
        Write-Verbose "$FunctionName - Scanning $path"
        $Results = Get-ChildItem -path $Path -include *.bak, *.trn
        return $Results
}