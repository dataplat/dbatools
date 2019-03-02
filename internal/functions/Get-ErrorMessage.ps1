function Get-ErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [System.Management.Automation.ErrorRecord]$Record
    )
    process {
        $innermessage = $Record.Exception.InnerException.InnerException.InnerException.InnerException.InnerException.Message
        if (-not $innermessage) { $innermessage = $Record.Exception.InnerException.InnerException.InnerException.InnerException.Message }
        if (-not $innermessage) { $innermessage = $Record.Exception.InnerException.InnerException.InnerException.Message }
        if (-not $innermessage) { $innermessage = $Record.Exception.InnerException.InnerException.Message }
        if (-not $innermessage) { $innermessage = $Record.Exception.InnerException.Message }
        if (-not $innermessage) { $innermessage = $Record.Exception.Message }
        return $innermessage
    }
}