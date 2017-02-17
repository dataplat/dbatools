Function Watch-DbaUpdate
{
<# 
.SYNOPSIS 
Watches the gallery for updates to dbatools. Mostly for fun.

.DESCRIPTION 
Watches the gallery for updates to dbatools. Only supports Windows 10.

.NOTES
Tags: JustForFun
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK 
https://dbatools.io/Watch-DbaUpdate

.EXAMPLE   
Watch-DbaUpdate

Watches the gallery for updates to dbatools.
#>	
	BEGIN
	{
		function Show-Notification (
				$title = "dbatools update",
				$text = "Version $galleryversion is now available"
			)
		{
			$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
			$templatetype = [Windows.UI.Notifications.ToastTemplateType]::ToastImageAndText01
			$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent($templatetype)
			
			#Convert to .NET type for XML manipuration
			$toastXml = [xml]$template.GetXml()
			$null = $toastXml.GetElementsByTagName("text").AppendChild($toastXml.CreateTextNode($title))
			
			$image = $toastXml.GetElementsByTagName("image")
			# unsure why $PSScriptRoot isnt't working here
			$base = $module.ModuleBase
			$image.setAttribute("src", "$base\bin\thor.png")
			$image.setAttribute("alt", "thor")
			
			#Convert back to WinRT type
			$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
			$xml.LoadXml($toastXml.OuterXml)
			
			$toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
			$toast.Tag = "PowerShell"
			$toast.Group = "PowerShell"
			$toast.ExpirationTime = [DateTimeOffset]::Now.AddHours(6)
			
			$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($text)
			$notifier.Show($toast)
		}
		
		function Create-Job
		{
			$script = {
				$scriptblock = [scriptblock]::Create('Watch-DbaUpdate')
				$trigger = New-JobTrigger -Once -At (Get-Date).Date -RepeatIndefinitely -RepetitionInterval (New-TimeSpan -Minutes 5)
				$options = New-ScheduledJobOption -ContinueIfGoingOnBattery -StartIfOnBattery
				Register-ScheduledJob -Name 'dbatools version check' -ScriptBlock $scriptblock -Trigger $trigger -ScheduledJobOption $options
			}
			
			If (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
			{
				Start-Process powershell -Verb runAs -ArgumentList $script.tostring()
			}
			else
			{
				$null = Invoke-Command -ScriptBlock $script
			}
		}
	}
	
	PROCESS
	{
		if (([Environment]::OSVersion).Version.Major -lt 10)
		{
			Write-Warning "This command only supports Windows 10 and above"
			return
		}
		
		if ($null -eq (Get-ScheduledJob -Name "dbatools version check" -ErrorAction SilentlyContinue))
		{
			Write-Warning "Watch-DbaUpdate runs as a Scheduled Job which must be created. This will only happen once."
			
			Create-Job
			
			Start-Sleep -Seconds 2
			
			if ($null -eq (Get-ScheduledJob -Name "dbatools version check" -ErrorAction SilentlyContinue))
			{
				Write-Warning "Couldn't create job :("
				return
			}
			else
			{
				$module = Get-Module -Name dbatools
				Write-Warning "Job created! A notication should appear momentarily. Here's something cute to look at in the interim."
				Show-Notification -title "dbatools ❤ you" -text "come hang out at dbatools.io/slack"
				return
			}
		}
		
		# leave this in for the workflow
		$module = Get-Module -Name dbatools
		
		if (!$module)
		{
			Import-Module dbatools
			$module = Get-Module -Name dbatools
		}
		
		#$findmodule = Find-Module -Name dbatools -Repository PSGallery
		#$currentversion = $findmodule.Version
		$galleryversion = [version]"0.8.903"
		$localversion = $module.Version
		if ($galleryversion -le $localversion) { return }
		#if ($findmodule.PublishedDate -gt (Get-Date).AddDays(-1)) { return }
		
		Show-Notification
	}
}