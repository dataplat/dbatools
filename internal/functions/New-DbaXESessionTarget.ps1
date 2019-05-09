function New-DbaXESessionTarget {
    <#
    .SYNOPSIS
    Not ready yet for prod.

    .DESCRIPTION

    .PARAMETER Name

    .PARAMETER Description

    .PARAMETER InputObject

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Xevent
        Author: Chrissy LeMaire (@cl)
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaXESessionTarget

    .EXAMPLE
        PS C:\> $hash = @()
        PS C:\> $hash = @{ Name = 'filename'; Value = 'system_health.xel' }
        PS C:\> $hash = @{ Name = 'increment'; Value = -1 }
        PS C:\> $hash = @{ Name = 'max_file_size'; Value = 10 }
        PS C:\> New-DbaXESessionTarget -Name "my dumb file" -Description "What" -FieldHash $hash

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [string]$Name,
        [string]$Description,
        [parameter(Mandatory)]
        [hashtable[]]$FieldHash,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.XEvent.Session[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        $targetfield = @()
        foreach ($value in $FieldHash) {
            $field = New-Object -TypeName Microsoft.SqlServer.Management.XEvent.TargetField
            $field.Name = $value.Name
            $field.Value = $value.Value
            $targetfield += $field
        }
    }
    process {
        try {
            $object = New-Object -TypeName Microsoft.SqlServer.Management.XEvent.Target
            $object.Name = $Name
            $object.Description = $Description
            $object.TargetFields = $targetfield

            foreach ($session in $InputObject) {
                $session.AddTarget($object)
            }
        } catch {
            Stop-Function -Message "Failure" -ErrorRecord $_
            return
        }
    }
}