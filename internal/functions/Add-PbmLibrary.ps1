function Add-PbmLibrary {
    param(
        [switch]$EnableException
    )
    try {
        if ($PSVersionTable.PSEdition -eq "Core") {
            $platformlib = Join-DbaPath -Path $script:libraryroot -ChildPath lib, net6.0
            $dmfdll = Join-DbaPath -Path $platformlib -ChildPath Microsoft.SqlServer.Dmf.dll
            $dmfcommon = Join-DbaPath -Path $platformlib -ChildPath Microsoft.SqlServer.Dmf.Common.dll
        } else {
            $platformlib = Join-DbaPath -Path $script:libraryroot -ChildPath lib, net462
            $dmfdll = Join-DbaPath -Path $platformlib -ChildPath Microsoft.SqlServer.Dmf.dll
            $dmfcommon = Join-DbaPath -Path $platformlib -ChildPath Microsoft.SqlServer.Dmf.Common.dll
        }

        Add-Type -Path $dmfcommon -ErrorAction Stop
        Add-Type -Path $dmfdll -ErrorAction Stop
    } catch {
        Stop-Function -Message "Could not load DMF libraries" -ErrorRecord $PSItem
        return
    }
}