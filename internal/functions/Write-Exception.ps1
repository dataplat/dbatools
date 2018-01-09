function Write-Exception {
    <#
    .SYNOPSIS
        Internal function. Writes exception to disk (my docs\dbatools-exceptions.txt) for later analysis.

    .PARAMETER e
        Exception

    .EXAMPLE
        Write-Exception $_
        Writes inner exception to disk

#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$e
    )

    $docs = [Environment]::GetFolderPath("mydocuments")
    $errorlog = "$docs\dbatools-exceptions.txt"
    $message = $e.Exception
    $invocation = $e.InvocationInfo

    $position = $invocation.PositionMessage
    $scriptname = $invocation.ScriptName
    if ($null -eq $e.Exception.InnerException) { $message = $e.Exception.InnerException }

    $message = $message.ToString()

    Add-Content $errorlog $(Get-Date)
    Add-Content $errorlog $scriptname
    Add-Content $errorlog $position
    Add-Content $errorlog $message
    Write-Message -Level Warning -Message "See error log $(Resolve-Path $errorlog) for more details."
}
