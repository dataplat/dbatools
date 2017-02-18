Function Watch-DbaUpdate
{
<# 
.SYNOPSIS 
Just for fun - watches the PowerShell Gallery for updates to dbatools - notifies max every 6 hours.

.DESCRIPTION 
Only supports Windows 10. Not sure how to make the notification last longer (like Slack does).
	
Anyone know how to make it clickable so that it opens an URL?

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
			$templatetype = [Windows.UI.Notifications.ToastTemplateType]::ToastImageAndText02
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
		
		function Create-Task
		{
			$script = {
				try
				{
					$action = New-ScheduledTaskAction –Execute 'powershell.exe' -Argument '–NoProfile -NoLogo -NonInteractive -WindowStyle Hidden Watch-DbaUpdate'
					$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 1)
					$principal = New-ScheduledTaskPrincipal -LogonType S4U -UserId (whoami)
					$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([timespan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd
					$task = Register-ScheduledTask -Principal $principal -TaskName 'dbatools version check' -Action $action -Trigger $trigger -Settings $settings -ErrorAction Stop
					return $true	
				}
				catch
				{
					return $false
				}
			}
			
			# Needs admin creds to setup the kind of PowerShell window that doesn't appear for a millisecond
			# which is a millisecond too long
			If (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
			{
				return (Start-Process powershell -Verb runAs -ArgumentList $script.tostring() -ErrorAction Stop)
			}
			else
			{
				return (Invoke-Command -ScriptBlock $script -ErrorAction Stop)
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
		
		if ($null -eq (Get-ScheduledTask -TaskName "dbatools version check" -ErrorAction SilentlyContinue))
		{
			Write-Warning "Watch-DbaUpdate runs as a Scheduled Task which must be created. This will only happen once."
			
			$result = Create-Task
			
			if ($result -eq $false)
			{
				Write-Warning "Couldn't create task :("
				return
			}
			else
			{
				$module = Get-Module -Name dbatools
				Write-Warning "Task created! A notication should appear momentarily. Here's something cute to look at in the interim."
				Show-Notification -title "dbatools ❤ you" -text "come hang out at dbatools.io/slack"
				return
			}
		}
		
		# leave this in for the scheduled task
		$module = Get-Module -Name dbatools
		
		if (!$module)
		{
			Import-Module dbatools
			$module = Get-Module -Name dbatools
		}
		
		$galleryversion = (Find-Module -Name dbatools -Repository PSGallery).Version
		$localversion = $module.Version
		
		if ($galleryversion -le $localversion) { return }
		
		$file = "$env:LOCALAPPDATA\dbatools\watchupdate.xml"
		
		$new = [pscustomobject]@{
			NotifyTime = (Get-Date)
			NotifyVersion = $galleryversion
		}
		
		if (Test-Path $file)
		{
			$old = Import-Clixml -Path $file -ErrorAction SilentlyContinue
			
			if ($old.NotifyTime -lt (Get-Date).AddHours(-6))
			{
				Export-Clixml -InputObject $new -Path $file
				Show-Notification
			}
		}
		else
		{
			$directory = Split-Path $file
			
			if (!(Test-Path $directory))
			{
				$null = New-Item -ItemType Directory -Path $directory
			}
			
			Export-Clixml -InputObject $new -Path $file
			Show-Notification
		}
	}
}