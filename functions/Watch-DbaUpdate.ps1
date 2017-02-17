Function Watch-DbaUpdate
{
<# 
.SYNOPSIS 
Watches the gallery for updates to dbatools.

.DESCRIPTION 
Watches the gallery for updates to dbatools. Only supports Windows 10.

.NOTES
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK 
https://dbatools.io/Watch-DbaUpdate

.EXAMPLE   
Watch-DbaUpdate

Watches the gallery for udpates to dbatools.

#>	
	PROCESS
	{
		if (([Environment]::OSVersion).Version.Major -lt 10)
		{
			Write-Warning "This command only supports Windows 10 and above"
			return
		}
		
		if (!(Get-Module -Name dbatools)) { Import-Module dbatools }
		
		$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
		$templatetype = [Windows.UI.Notifications.ToastTemplateType]::ToastImageAndText03
		$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent($templatetype)
		
		#Convert to .NET type for XML manipuration
		$toastXml = [xml]$template.GetXml()
		$null = $toastXml.GetElementsByTagName("text").AppendChild($toastXml.CreateTextNode("dbatools update"))
		
		$image = $toastXml.GetElementsByTagName("image")
		$image.setAttribute("src", "$PSScriptRoot\bin\thor.png")
		$image.setAttribute("alt", "thor")
		
		#Convert back to WinRT type
		$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
		$xml.LoadXml($toastXml.OuterXml)
		
		$toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
		$toast.Tag = "PowerShell"
		$toast.Group = "PowerShell"
		$toast.ExpirationTime = [DateTimeOffset]::Now.AddMinutes(5)
		
		$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("new version")
		$notifier.Show($toast)
		
<#
workflow Resume_Workflow
{
	
}
# Create the scheduled job properties
$options = New-ScheduledJobOption -ContinueIfGoingOnBattery -StartIfOnBattery
$AtStartup = New-JobTrigger -AtStartup
$scriptblock = { Resume-Job -Name new_resume_workflow_job -Wait }

# Register the scheduled job
Register-ScheduledJob -Name Resume_Workflow_Job -Trigger $AtStartup -ScriptBlock $scriptblock -ScheduledJobOption $options

# Execute the workflow as a new job
Resume_Workflow -AsJob -JobName new_resume_workflow_job
#>
	}
}

Watch-DbaUpdate