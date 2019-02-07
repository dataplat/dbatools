Function Copy-DbaObject {
    <#
        .SYNOPSIS
            Deep copies an object to avoid copy by reference issues

        .DESCRIPTION
            Should create

        .PARAMETER InputObject

            The object to be copied

        .NOTES
            Tags: Internal
            Author: Stuart Moore (@napalmgram)

            Website: https://dbatools.io
            Copyright: (c) 2019 by dbatools, licensed under MIT
-           License: MIT https://opensource.org/licenses/MIT

        .LINK
            --internal function, not exposed to end user

        .EXAMPLE
            $copyBackupHistory = Copy-DbaObject -InputObject $BackupHistory

            returns a distinct (ie; not by reference) copy of $BackupHistory
       #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [Object]$inputObject
    )
    foreach ($object in $inputObject) {
        try {
            $returnObject = New-Object $object.PsObject.TypeNames[0]
        } catch {
            #fall back to a generic object
            $returnObject = New-Object System.Object
        }
        $object.PsObject.Properties | ForEach-Object {
            if ($_.name -notin $returnObject.PsObject.Members.Name) {
                Add-Member -InputObject $returnObject -NotePropertyName $_.Name -NotePropertyValue $null
            }
            if ($_.TypeNameOfValue -ne 'System.Object') {
                $returnObject.($_.Name) = $_.Value
            } else {
                $returnObject.($_.name) = Copy-DbaObject $_.value
            }
        }
        $returnObject
    }
}