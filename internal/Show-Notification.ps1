function Show-Notification (
	$title = "dbatools update",
	$text = "Version $galleryversion is now available"
)
{
	$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
	$templatetype = [Windows.UI.Notifications.ToastTemplateType]::ToastImageAndText02
	$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent($templatetype)
	
	$toastXml = [xml]$template.GetXml()
	$toastTextElements = $toastXml.GetElementsByTagName("text")
	
	$null = $toastTextElements[0].AppendChild($toastXml.CreateTextNode($title))
	$null = $toastTextElements[1].AppendChild($toastXml.CreateTextNode($text))
	
	# make it last longer
	#$singletoast = $toastXml.SelectSingleNode("/toast")
	#$singletoast.SetAttribute("duration", "long")
	
	$image = $toastXml.GetElementsByTagName("image")
	$base = $module.ModuleBase
	
	$image.setAttribute("src", "$base\bin\thor.png")
	$image.setAttribute("alt", "thor")
	
	$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
	$xml.LoadXml($toastXml.OuterXml)
	
	$toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
	$toast.Tag = "PowerShell"
	$toast.Group = "dbatools"
	$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("dbatools").Show($toast)
}
		