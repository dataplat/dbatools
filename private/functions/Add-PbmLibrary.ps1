function Add-PbmLibrary {
    param(
        [switch]$EnableException
    )
    try {
        if ($IsWindows -and $PSVersionTable.PSEdition -eq 'Desktop') {
            $platformlib = Join-DbaPath -Path $script:libraryroot -ChildPath 'desktop', 'lib'
        } else {
            $platformlib = Join-DbaPath -Path $script:libraryroot -ChildPath 'core', 'lib'
        }
        $dmfdll = Join-DbaPath -Path $platformlib -ChildPath 'Microsoft.SqlServer.Dmf.dll'
        $dmfcommon = Join-DbaPath -Path $platformlib -ChildPath 'Microsoft.SqlServer.Dmf.Common.DLL'
        Add-Type -Path $dmfcommon -ErrorAction Stop
        Add-Type -Path $dmfdll -ErrorAction Stop
    } catch {
        Stop-Function -Message "Could not load DMF libraries" -ErrorRecord $PSItem
        return
    }
}