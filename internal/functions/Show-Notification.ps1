function Show-Notification {
    param(
        $GalleryVersion,
        $Title = "dbatools update",
        $Text = "Version $GalleryVersion is now available"
    )
    # ensure the dbatools 'app' exists in registry so that it doesn't immediately disappear from Action Center
    $regPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings'
    $appId = "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"

    if (!(Test-Path -Path "$regPath\$appId")) {
        Write-Verbose "Adding required registry entry at $("$regPath\$appId")"
        $null = New-Item -Path "$regPath\$appId" -Force
        $null = New-ItemProperty -Path "$regPath\$appId" -Name 'ShowInActionCenter' -Value 1 -PropertyType 'DWORD' -Force
    }
    $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $template = [Windows.UI.Notifications.ToastTemplateType]::ToastImageAndText02
    [xml]$toastTemplate = ([Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent($template).GetXml())

    [xml]$toastTemplate = "
    <toast launch=`"app-defined-string`">
        <visual>
            <binding template=`"ToastGeneric`">
                <text>`"$Title`"</text>
                <text>`"$Text`"</text>
            </binding>
        </visual>
        <actions>
            <action activationType=`"background`" content=`"OK`" arguments=`"later`"/>
        </actions>
    </toast>"

    $toastXml = New-Object -TypeName Windows.Data.Xml.Dom.XmlDocument
    $toastXml.LoadXml($toastTemplate.OuterXml)

    $notify = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId)
    $notify.Show($toastXml)
}