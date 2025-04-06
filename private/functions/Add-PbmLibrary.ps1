function Add-PbmLibrary {
    param(
        [switch]$EnableException
    )
    try {
        $platformlib = Join-DbaPath -Path $script:libraryroot -ChildPath lib

        if ($PSVersionTable.PSEdition -eq 'Core') {
            $platformlib = Join-DbaPath -Path $platformlib -ChildPath core
        } else {
            $platformlib = Join-DbaPath -Path $platformlib -ChildPath desktop
        }

        $dmfdll = Join-DbaPath -Path $platformlib -ChildPath Microsoft.SqlServer.Dmf.dll
        $dmfcommon = Join-DbaPath -Path $platformlib -ChildPath Microsoft.SqlServer.Dmf.Common.DLL
        Add-Type -Path $dmfcommon -ErrorAction Stop
        Add-Type -Path $dmfdll -ErrorAction Stop
    } catch {
        Stop-Function -Message "Could not load DMF libraries" -ErrorRecord $PSItem
        return
    }
}