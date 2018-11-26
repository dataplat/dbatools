function Invoke-DbatoolsRenameHelper {
    <#
    .SYNOPSIS
        Older dbatools command names have been changed. This script helps keep up.

    .DESCRIPTION
        Older dbatools command names have been changed. This script helps keep up.

    .PARAMETER InputObject
        A piped in object from Get-ChildItem

    .PARAMETER Encoding
        Specifies the file encoding. The default is UTF8.

        Valid values are:
        -- ASCII: Uses the encoding for the ASCII (7-bit) character set.
        -- BigEndianUnicode: Encodes in UTF-16 format using the big-endian byte order.
        -- Byte: Encodes a set of characters into a sequence of bytes.
        -- String: Uses the encoding type for a string.
        -- Unicode: Encodes in UTF-16 format using the little-endian byte order.
        -- UTF7: Encodes in UTF-7 format.
        -- UTF8: Encodes in UTF-8 format.
        -- Unknown: The encoding type is unknown or invalid. The data can be treated as binary.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command

    .NOTES
        Tags: Module
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbatoolsRenameHelper

    .EXAMPLE
        PS C:\> Get-ChildItem C:\temp\ps\*.ps1 -Recurse | Invoke-DbatoolsRenameHelper

        Checks to see if any ps1 file in C:\temp\ps matches an old command name.
        If so, then the command name within the text is updated and the resulting changes are written to disk in UTF-8.

    .EXAMPLE
        PS C:\> Get-ChildItem C:\temp\ps\*.ps1 -Recurse | Invoke-DbatoolsRenameHelper -Encoding Ascii -WhatIf

        Shows what would happen if the command would run. If the command would run and there were matches,
        the resulting changes would be written to disk as Ascii encoded.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [System.IO.FileInfo[]]$InputObject,
        [ValidateSet('ASCII', 'BigEndianUnicode', 'Byte', 'String', 'Unicode', 'UTF7', 'UTF8', 'Unknown')]
        [string]$Encoding = 'UTF8',
        [switch]$EnableException
    )
    begin {
        $morerenames = @(
            @{
                "AliasName"  = "Invoke-Sqlcmd2"
                "Definition" = "Invoke-DbaQuery"
            },
            @{
                "AliasName"  = "UseLastBackups"
                "Definition" = "UseLastBackup"
            },
            @{
                "AliasName"  = "NetworkShare"
                "Definition" = "SharedPath"
            },
            @{
                "AliasName"  = "NoSystemLogins"
                "Definition" = "ExcludeSystemLogins"
            },
            @{
                "AliasName"  = "NoJobSteps"
                "Definition" = "ExcludeJobSteps"
            },
            @{
                "AliasName"  = "NoSystemObjects"
                "Definition" = "ExcludeSystemObjects"
            },
            @{
                "AliasName"  = "NoJobs"
                "Definition" = "ExcludeJobs"
            },
            @{
                "AliasName"  = "NoDatabases"
                "Definition" = "ExcludeDatabases"
            },
            @{
                "AliasName"  = "NoDisabledJobs"
                "Definition" = "ExcludeDisabledJobs"
            },
            @{
                "AliasName"  = "NoJobSteps"
                "Definition" = "ExcludeJobSteps"
            },
            @{
                "AliasName"  = "NoSystem"
                "Definition" = "ExcludeSystemLogins"
            },
            @{
                "AliasName"  = "NoSystemDb"
                "Definition" = "ExcludeSystem"
            },
            @{
                "AliasName"  = "NoSystemObjects"
                "Definition" = "ExcludeSystemObjects"
            },
            @{
                "AliasName"  = "NoSystemSpid"
                "Definition" = "ExcludeSystemSpids"
            },
            @{
                "AliasName"  = "NoQueryTextColumn"
                "Definition" = "ExcludeQueryTextColumn"
            },
            @{
                "AliasName"  = "ExcludeAllSystemDb"
                "Definition" = "ExcludeSystem"
            },
            @{
                "AliasName"  = "ExcludeAllUserDb"
                "Definition" = "ExcludeUser"
            }
        )

        $allrenames = $script:renames + $morerenames
    }
    process {
        foreach ($fileobject in $InputObject) {
            $file = $fileobject.FullName

            foreach ($name in $allrenames) {
                if ((Select-String -Pattern $name.AliasName -Path $file)) {
                    if ($Pscmdlet.ShouldProcess($file, "Replacing $($name.AliasName) with $($name.Definition)")) {
                        $content = (Get-Content -Path $file -Raw).Replace($name.AliasName, $name.Definition).Trim()
                        Set-Content -Path $file -Encoding $Encoding -Value $content
                        [pscustomobject]@{
                            Path         = $file
                            Pattern      = $name.AliasName
                            ReplacedWith = $name.Definition
                        }
                    }
                }
            }
        }
    }
}