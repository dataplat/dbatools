#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Test-NotWindows {
    <#
        .SYNOPSIS
            Internal tool, used to detect non-Windows platforms

        .DESCRIPTION
            Some things don't work with Windows, this is an easy way to detect

        .EXAMPLE
            if (Test-NotWindows) { return }

            The calling function will stop if this function returns true.
       #>
    [CmdletBinding()]
    param (
        
    )
    
    if (($PSVersionTable.Keys -contains "Platform") -and $psversiontable.Platform -ne "Win32NT1") {
        Write-Message -Level Warning -Message "This command is not supported on non-Windows platforms :("
        return $true
    }
    
    return $false
}