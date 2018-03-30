function Watch-DbaUpdate {
    <#
        .SYNOPSIS
            Just for fun - checks the PowerShell Gallery every 1 hour for updates to dbatools. Notifies once per release.

        .DESCRIPTION
            Just for fun - checks the PowerShell Gallery every 1 hour for updates to dbatools. Notifies once max per release.

            Anyone know how to make it clickable so that it opens an URL?

        .NOTES
            Tags: JustForFun, Module
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Watch-DbaUpdate

        .EXAMPLE
            Watch-DbaUpdate

            Watches the gallery for updates to dbatools.
    #>

    process {
        if (([Environment]::OSVersion).Version.Major -lt 10) {
            Write-Warning "This command only supports Windows 10 and higher."
            return
        }

        if ($null -eq (Get-ScheduledTask -TaskName "dbatools version check" -ErrorAction SilentlyContinue)) {
            Install-DbaWatchUpdate
        }

        # leave this in for the scheduled task
        $module = Get-Module -Name dbatools

        if (!$module) {
            Import-Module dbatools
            $module = Get-Module -Name dbatools
        }

        $galleryVersion = (Find-Module -Name dbatools -Repository PSGallery).Version
        $localVersion = $module.Version

        if ($galleryVersion -le $localVersion) { return }

        $file = "$env:LOCALAPPDATA\dbatools\watchupdate.xml"

        $new = [pscustomobject]@{
            NotifyVersion = $galleryVersion
        }

        # now that notifications stay until they are checked, we just have to keep
        # track of the last version we notified about

        if (Test-Path $file) {
            $old = Import-Clixml -Path $file -ErrorAction SilentlyContinue

            if ($galleryVersion -gt $old.NotifyVersion) {
                Export-Clixml -InputObject $new -Path $file
                Show-Notification
            }
        }
        else {
            $directory = Split-Path $file

            if (!(Test-Path $directory)) {
                $null = New-Item -ItemType Directory -Path $directory
            }

            Export-Clixml -InputObject $new -Path $file
            Show-Notification
        }
    }
}
