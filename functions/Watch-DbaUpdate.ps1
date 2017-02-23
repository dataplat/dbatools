Function Watch-DbaUpdate
{
<# 
.SYNOPSIS 
Just for fun - checks the PowerShell Gallery ever few hours for updates to dbatools - notifies max every 6 hours.

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
		function Create-Task
		{
			$script = {
				try
				{
					# create a task, check every 3 hours
					$action = New-ScheduledTaskAction –Execute 'powershell.exe' -Argument '–NoProfile -NoLogo -NonInteractive -WindowStyle Hidden Watch-DbaUpdate'
					$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Hours 3)
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
			Install-DbaWatchUpdate
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