function Show-Notification {
    param(
        $Title = "dbatools update",
        $Text = "Version $galleryVersion is now available"
    )
    # ensure the dbatools 'app' exists in registry so that it doesn't immediately disappear from Action Center
    $regpath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings'
    $appid = "dbatools"

    if (!(Test-Path -Path "$regpath\$appid")) {
        Write-Verbose "Adding required registry entry at $("$regpath\$appid")"
        $null = New-Item -Path $regpath -Name $appid
        $null = New-ItemProperty -Path "$regpath\$appid" -Name 'ShowInActionCenter' -Value 1 -PropertyType 'DWORD'
    }

    $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $templateType = [Windows.UI.Notifications.ToastTemplateType]::ToastImageAndText02
    $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent($templateType)

    $toastXml = [xml]$template.GetXml()
    $toastTextElements = $toastXml.GetElementsByTagName("text")

    $null = $toastTextElements[0].AppendChild($toastXml.CreateTextNode($Title))
    $null = $toastTextElements[1].AppendChild($toastXml.CreateTextNode($Text))

    $image = $toastXml.GetElementsByTagName("image")
    $base = $module.ModuleBase

    $image.setAttribute("src", "$base\bin\thor.png")
    $image.setAttribute("alt", "thor")

    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($toastXml.OuterXml)

    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
    $toast.Tag = "PowerShell"
    $toast.Group = "dbatools"
    $null = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("dbatools").Show($toast)
}