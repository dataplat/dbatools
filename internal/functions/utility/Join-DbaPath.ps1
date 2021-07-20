function Join-DbaPath {
    <#
    .SYNOPSIS
        Performs multisegment path joins.

    .DESCRIPTION
        Performs multisegment path joins.

    .PARAMETER Path
        The basepath to join on.

    .PARAMETER Child
        Any number of child paths to add.

    .EXAMPLE
        PS C:\> Join-DbaPath -Path 'C:\temp' 'Foo' 'Bar'

        Returns 'C:\temp\Foo\Bar' on windows.
        Returns 'C:/temp/Foo/Bar' on non-windows.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,
        [dbainstanceparameter]$SqlInstance,
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Child
    )

    if (-not $SqlInstance) {
        return @($path) + $Child -join
        [IO.Path]::DirectorySeparatorChar -replace
        '\\|/', [IO.Path]::DirectorySeparatorChar
    }

    $resultingPath = $Path

    if (Test-HostOSLinux -SqlInstance $SqlInstance) {
        Write-Message -Level Verbose -Message "Linux detected on remote server"
        $resultingPath = $resultingPath.Replace("\", "/")

        foreach ($childItem in $Child) {
            $resultingPath = ($resultingPath, $childItem) -join '/'
        }
    } else {
        if (($PSVersionTable.PSVersion.Major -ge 6) -and (-not $script:isWindows)) {
            $resultingPath = $resultingPath.Replace("\", "/")
        } else {
            $resultingPath = $resultingPath.Replace("/", "\")
        }

        foreach ($childItem in $Child) {
            $resultingPath = [IO.Path]::Combine($resultingPath, $childItem)
        }
    }

    $resultingPath
}