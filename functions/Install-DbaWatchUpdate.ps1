Function Install-DbaWatchUpdate
{
<# 
.SYNOPSIS 
Adds the scheduled task to support Watch-DbaUpdate

.DESCRIPTION 
Adds the scheduled task to support Watch-DbaUpdate.

.NOTES
Tags: JustForFun
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK 
https://dbatools.io/Install-DbaWatchUpdate

.EXAMPLE   
Install-DbaWatchUpdate

Adds the scheduled task needed by Watch-DbaUpdate
#>
	PROCESS
	{
		if (([Environment]::OSVersion).Version.Major -lt 10)
		{
			Write-Warning "This command only supports Windows 10 and above"
			return
		}
		
		$script = {
			try
			{
				# create a task, check every 3 hours
				$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -NoLogo -NonInteractive -WindowStyle Hidden Watch-DbaUpdate'
				$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Hours 1)
				$principal = New-ScheduledTaskPrincipal -LogonType S4U -UserId (whoami)
				$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([timespan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd
				$task = Register-ScheduledTask -Principal $principal -TaskName 'dbatools version check' -Action $action -ServerTrigger $trigger -Settings $settings -ErrorAction Stop
			}
			catch
			{
				# keep movin
			}
		}
		
		if ($null -eq (Get-ScheduledTask -TaskName "dbatools version check" -ErrorAction SilentlyContinue))
		{
			# Needs admin creds to setup the kind of PowerShell window that doesn't appear for a millisecond
			# which is a millisecond too long
			If (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
			{
				Write-Warning "Watch-DbaUpdate runs as a Scheduled Task which must be created. This will only happen once."
				Start-Process powershell -Verb runAs -ArgumentList Install-DbaWatchUpdate -Wait
			}
			
			try
			{
				Invoke-Command -ScriptBlock $script -ErrorAction Stop
				
				if ((Get-Location).Path -ne "$env:windir\system32")
				{
					$module = Get-Module -Name dbatools
					Write-Warning "Task created! A notication should appear momentarily. Here's something cute to look at in the interim."
					Show-Notification -title "dbatools wants you" -text "come hang out at dbatools.io/slack"
				}
			}
			catch
			{
				Write-Warning "Couldn't create scheduled task :("
				return
			}
			
			# doublecheck
			if ($null -eq (Get-ScheduledTask -TaskName "dbatools version check" -ErrorAction SilentlyContinue))
			{
				Write-Warning "Couldn't create scheduled task :("
			}
		}
		else
		{
			Write-Output "Watch-DbaUpdate is already installed :)"
			Write-Output "And by already isntalled, we mean it's a scheduled task called 'dbatools version check'"
		}
	}
}
